
--[[
========================================================
                     VEZA GUI v3.4
========================================================
MODULES
  1. Vehicle Tracker
  2. Distance Settings
  3. Zombie ESP
  4. Vehicle ESP + Selected Vehicle Tracer

VEHICLE TRACKER
  - Vehicle name
  - Distance in studs
  - Relative direction
  - Select target
  - Live updates
  - Configurable scan radius

ZOMBIE ESP
  - Green Highlight
  - Automatic zombie detection
  - Toggle ON / OFF
  - Cleanup on disable

GUI
  - Modular sidebar
  - Draggable
  - Minimize / Close
  - Mouse + Touch support

NOTE:
Local visual effects only.
Max distance filters replicated vehicles.
Does not override Roblox streaming.
========================================================
]]

--========================================================
-- SERVICES
--========================================================

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

--========================================================
-- CLEANUP PREVIOUS VERSION
--========================================================

if _G.VezaStop then
    pcall(_G.VezaStop)
end

local previous = PlayerGui:FindFirstChild("VezaGUI")
if previous then
    previous:Destroy()
end

--========================================================
-- SETTINGS
--========================================================

local Settings = {
    MaxDistance = 1000,
    UnlimitedDistance = false,

    ScanInterval = 1,
    UpdateInterval = 0.15,
    ZombieScanInterval = 0.75,
}

--========================================================
-- PERSISTENT CONFIG + HUSH CAMERA ZOOM
--========================================================

local HttpService = game:GetService("HttpService")
local CONFIG_FILE = "VEZA_GUI_settings.json"
local VEHICLE_LISTS_FILE = "VEZA_GUI_vehicle_lists.json"

-- Vehicle preference tables are independent from the general settings toggle.
local favoriteVehicles = {}
local ignoredVehicles = {}

local zombieESPEnabled = true
local vehicleESPEnabled = true
local militaryMapEnabled = true
local updateMilitaryToggle
local updateVehicleToggle
local updateZombieToggle

local RememberSettings = true
local ZoomEnabled = true
local ZoomDistance = 300
local SavedZoomOriginal = nil
local CameraZoomController = nil

local function canUseFileAPI()
    return type(readfile) == "function"
        and type(writefile) == "function"
        and type(isfile) == "function"
end

local function ensureConfigFolder()
    if type(isfolder) == "function"
        and type(makefolder) == "function" then
        pcall(function()
            if not isfolder("VEZA_GUI") then
                makefolder("VEZA_GUI")
            end
        end)
    end
end

local function loadVehicleLists()
    if not canUseFileAPI() then return end
    local ok, raw = pcall(function()
        if isfile(VEHICLE_LISTS_FILE) then return readfile(VEHICLE_LISTS_FILE) end
        return nil
    end)
    if not ok or type(raw) ~= "string" or raw == "" then return end
    local decodedOK, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not decodedOK or type(data) ~= "table" then return end
    if type(data.Favorites) == "table" then
        for _, name in ipairs(data.Favorites) do
            if type(name) == "string" then favoriteVehicles[name] = true end
        end
    end
    if type(data.Ignored) == "table" then
        for _, name in ipairs(data.Ignored) do
            if type(name) == "string" then ignoredVehicles[name] = true end
        end
    end
end

local function saveVehicleLists()
    if not canUseFileAPI() then return false end
    ensureConfigFolder()
    local favorites, ignored = {}, {}
    for name in pairs(favoriteVehicles) do table.insert(favorites, name) end
    for name in pairs(ignoredVehicles) do table.insert(ignored, name) end
    table.sort(favorites)
    table.sort(ignored)
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode({Favorites = favorites, Ignored = ignored})
    end)
    if not ok then return false end
    return pcall(function() writefile(VEHICLE_LISTS_FILE, encoded) end)
end

local function loadConfig()
    if not canUseFileAPI() then
        return
    end

    ensureConfigFolder()

    local ok, raw = pcall(function()
        if not isfile(CONFIG_FILE) then
            return nil
        end
        return readfile(CONFIG_FILE)
    end)

    if not ok or type(raw) ~= "string" or raw == "" then
        return
    end

    local decodedOK, data = pcall(function()
        return HttpService:JSONDecode(raw)
    end)

    if not decodedOK or type(data) ~= "table" then
        return
    end

    if type(data.RememberSettings) == "boolean" then
        RememberSettings = data.RememberSettings
    end

    if not RememberSettings then
        return
    end

    if type(data.MaxDistance) == "number" then
        Settings.MaxDistance = math.clamp(
            math.floor(data.MaxDistance), 100, 5000
        )
    end
    if type(data.UnlimitedDistance) == "boolean" then
        Settings.UnlimitedDistance = data.UnlimitedDistance
    end
    if type(data.ZombieESP) == "boolean" then
        _G.VEZA_LoadZombieESP = data.ZombieESP
    end
    if type(data.VehicleESP) == "boolean" then
        _G.VEZA_LoadVehicleESP = data.VehicleESP
    end
    if type(data.MilitaryMap) == "boolean" then
        _G.VEZA_LoadMilitaryMap = data.MilitaryMap
    end
    if type(data.ZoomEnabled) == "boolean" then
        ZoomEnabled = data.ZoomEnabled
    end
    if type(data.ZoomDistance) == "number" then
        ZoomDistance = math.clamp(
            math.floor(data.ZoomDistance), 1, 1000
        )
    end
end

local function saveConfig()
    if not RememberSettings then
        return false
    end
    if not canUseFileAPI() then
        return false
    end

    ensureConfigFolder()

    local data = {
        RememberSettings = RememberSettings,
        MaxDistance = Settings.MaxDistance,
        UnlimitedDistance = Settings.UnlimitedDistance,
        ZombieESP = zombieESPEnabled == true,
        VehicleESP = vehicleESPEnabled == true,
        MilitaryMap = militaryMapEnabled == true,
        ZoomEnabled = ZoomEnabled,
        ZoomDistance = ZoomDistance,
    }

    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    if not ok then
        return false
    end

    local writeOK = pcall(function()
        writefile(CONFIG_FILE, encoded)
    end)
    return writeOK
end

loadConfig()
loadVehicleLists()

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

local running = true
local selectedVehicle = nil

local vehicles = {}
local vehicleRows = {}
local bosses = {}
local bossRows = {}
local selectedBoss = nil
local compactMode = "Cars"
local minimized = false
local scanVehicles
local zombieHighlights = {}
local seenVehicleModels = {}
local seenBossModels = {}

local connections = {}

--========================================================
-- THEME
--========================================================

local Theme = {
    Background = Color3.fromRGB(17, 19, 24),
    Sidebar = Color3.fromRGB(14, 16, 20),
    Surface = Color3.fromRGB(27, 30, 37),
    SurfaceHover = Color3.fromRGB(36, 41, 50),
    Selected = Color3.fromRGB(30, 65, 68),

    Accent = Color3.fromRGB(40, 190, 153),
    Text = Color3.fromRGB(242, 244, 247),
    Muted = Color3.fromRGB(145, 152, 164),
    Border = Color3.fromRGB(48, 52, 61),
    Red = Color3.fromRGB(205, 75, 80),

    ZombieFill = Color3.fromRGB(40, 255, 120),
    ZombieOutline = Color3.fromRGB(0, 255, 90),
}

--========================================================
-- UI HELPERS
--========================================================

local function create(class, props, parent)
    local obj = Instance.new(class)

    for key, value in pairs(props or {}) do
        obj[key] = value
    end

    if parent then
        obj.Parent = parent
    end

    return obj
end

local function round(obj, radius)
    create("UICorner", {
        CornerRadius = UDim.new(0, radius or 6)
    }, obj)
end

local function addStroke(obj)
    create("UIStroke", {
        Color = Theme.Border,
        Thickness = 1,
        Transparency = 0.35
    }, obj)
end

local function text(parent, value, size, color, bold)
    return create("TextLabel", {
        BackgroundTransparency = 1,
        Text = value,
        TextColor3 = color or Theme.Text,
        Font = bold and Enum.Font.GothamBold
            or Enum.Font.Gotham,
        TextSize = size or 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd
    }, parent)
end

local function button(parent, value, color)
    local obj = create("TextButton", {
        BackgroundColor3 = color or Theme.Surface,
        BorderSizePixel = 0,
        Text = value,
        TextColor3 = Theme.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        AutoButtonColor = true
    }, parent)

    round(obj, 6)
    return obj
end

local function track(conn)
    table.insert(connections, conn)
    return conn
end

--========================================================
-- GUI ROOT
--========================================================

local gui = create("ScreenGui", {
    Name = "VezaGUI",
    ResetOnSpawn = false,
    DisplayOrder = 999,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling
}, PlayerGui)

local main = create("Frame", {
    Name = "Main",
    Size = UDim2.new(0, 580, 0, 390),
    Position = UDim2.new(0.5, -290, 0.5, -195),
    BackgroundColor3 = Theme.Background,
    BackgroundTransparency = 0.16,
    BorderSizePixel = 0,
    ClipsDescendants = true
}, gui)

round(main, 12)
addStroke(main)

-- RESPONSIVE SCALE
local scale = create("UIScale", {
    Scale = 1
}, main)

local function updateScale()
    local camera = workspace.CurrentCamera
    if not camera then return end

    local viewport = camera.ViewportSize

    local sx = (viewport.X - 20) / 580
    local sy = (viewport.Y - 20) / 390

    scale.Scale = math.clamp(
        math.min(sx, sy, 1),
        0.45,
        1
    )
end

updateScale()

--========================================================
-- HEADER
--========================================================

local header = create("Frame", {
    Size = UDim2.new(1, 0, 0, 46),
    BackgroundColor3 = Theme.Background,
    BackgroundTransparency = 0.14,
    BorderSizePixel = 0
}, main)

local logo = text(
    header, "VEZA", 19, Theme.Accent, true
)
logo.Position = UDim2.new(0, 17, 0, 7)
logo.Size = UDim2.new(0, 60, 0, 30)

local version = text(
    header, "v2.7", 10, Theme.Muted
)
version.Position = UDim2.new(0, 80, 0, 10)
version.Size = UDim2.new(0, 45, 0, 25)

local minimize = button(header, "—")
minimize.Position = UDim2.new(1, -76, 0, 9)
minimize.Size = UDim2.new(0, 29, 0, 28)

local close = button(header, "X", Theme.Red)
close.Position = UDim2.new(1, -40, 0, 9)
close.Size = UDim2.new(0, 29, 0, 28)

create("Frame", {
    Size = UDim2.new(1, 0, 0, 1),
    Position = UDim2.new(0, 0, 1, -1),
    BackgroundColor3 = Theme.Border,
    BorderSizePixel = 0
}, header)

--========================================================
-- DRAG WINDOW
--========================================================

local dragging = false
local dragStart
local startPos
local dragInput

track(header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then

        dragging = true
        dragStart = input.Position
        startPos = main.Position
        dragInput = input
    end
end))

track(UIS.InputChanged:Connect(function(input)
    if not dragging then return end

    local valid =
        input == dragInput
        or (
            dragInput
            and dragInput.UserInputType
                == Enum.UserInputType.MouseButton1
            and input.UserInputType
                == Enum.UserInputType.MouseMovement
        )

    if not valid then return end

    local delta = input.Position - dragStart
    local s = scale.Scale

    main.Position = UDim2.new(
        startPos.X.Scale,
        startPos.X.Offset + delta.X / s,
        startPos.Y.Scale,
        startPos.Y.Offset + delta.Y / s
    )
end))

track(UIS.InputEnded:Connect(function(input)
    if input == dragInput
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
        dragInput = nil
    end
end))

--========================================================
-- BODY
--========================================================

local body = create("Frame", {
    Size = UDim2.new(1, 0, 1, -46),
    Position = UDim2.new(0, 0, 0, 46),
    BackgroundTransparency = 1
}, main)

-- SIDEBAR
local sidebar = create("Frame", {
    Size = UDim2.new(0, 155, 1, 0),
    BackgroundColor3 = Theme.Sidebar,
    BackgroundTransparency = 0.14,
    BorderSizePixel = 0
}, body)

local sidebarTitle = text(
    sidebar, "FEATURES", 10, Theme.Muted, true
)
sidebarTitle.Position = UDim2.new(0, 14, 0, 14)
sidebarTitle.Size = UDim2.new(1, -25, 0, 20)

local navContainer = create("Frame", {
    Size = UDim2.new(1, -16, 0, 230),
    Position = UDim2.new(0, 8, 0, 42),
    BackgroundTransparency = 1
}, sidebar)

create("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder
}, navContainer)

local footer = text(
    sidebar, "VEZA  •  Modular GUI", 10, Theme.Muted
)
footer.Position = UDim2.new(0, 13, 1, -30)
footer.Size = UDim2.new(1, -20, 0, 20)

-- CONTENT
local content = create("Frame", {
    Size = UDim2.new(1, -155, 1, 0),
    Position = UDim2.new(0, 155, 0, 0),
    BackgroundTransparency = 1
}, body)

local pages = {}
local navButtons = {}

local function showPage(name)
    for pageName, page in pairs(pages) do
        page.Visible = pageName == name
    end

    for pageName, nav in pairs(navButtons) do
        nav.BackgroundColor3 =
            pageName == name
            and Theme.Selected
            or Theme.Sidebar

        nav.TextColor3 =
            pageName == name
            and Theme.Accent
            or Theme.Muted
    end
end

local function registerPage(name, navName, order)
    local nav = button(navContainer, navName, Theme.Sidebar)
    nav.Size = UDim2.new(1, 0, 0, 36)
    nav.LayoutOrder = order
    nav.TextXAlignment = Enum.TextXAlignment.Left
    nav.TextSize = 11

    create("UIPadding", {
        PaddingLeft = UDim.new(0, 12)
    }, nav)

    local page = create("Frame", {
        Name = name,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Visible = false
    }, content)

    pages[name] = page
    navButtons[name] = nav

    nav.MouseButton1Click:Connect(function()
        showPage(name)
    end)

    return page
end

--========================================================
-- PAGE 1: VEHICLE TRACKER
--========================================================

-- Top-center detection notifications. Each alert has its own close button.
local notificationLayer = create("Frame", {
    Name = "VEZA_NotificationLayer",
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 10),
    Size = UDim2.new(0, 360, 0, 150),
    BackgroundTransparency = 1,
    ZIndex = 100
}, screenGui)
local notificationLayout = create("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Center
}, notificationLayer)
local notificationSerial = 0

local function showDetectionNotification(kind, itemName)
    notificationSerial += 1
    local card = create("Frame", {
        Name = "DetectionAlert",
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        ZIndex = 101,
        LayoutOrder = notificationSerial
    }, notificationLayer)
    create("UICorner", {CornerRadius = UDim.new(0, 7)}, card)
    create("UIStroke", {Color = Theme.Accent, Transparency = 0.35, Thickness = 1}, card)

    local message = text(card, kind .. " detected: " .. itemName, 11, Theme.Text, true)
    message.Position = UDim2.new(0, 12, 0, 0)
    message.Size = UDim2.new(1, -48, 1, 0)
    message.TextXAlignment = Enum.TextXAlignment.Left
    message.ZIndex = 102

    local closeAlert = button(card, "×", Theme.Border)
    closeAlert.Position = UDim2.new(1, -34, 0, 7)
    closeAlert.Size = UDim2.new(0, 26, 0, 28)
    closeAlert.ZIndex = 103
    closeAlert.MouseButton1Click:Connect(function()
        card:Destroy()
    end)
end

local trackerPage = registerPage(
    "Tracker", "Vehicle Tracker", 1
)

local trackerTitle = text(
    trackerPage, "Vehicle Tracker", 16, Theme.Text, true
)
trackerTitle.Position = UDim2.new(0, 16, 0, 12)
trackerTitle.Size = UDim2.new(1, -32, 0, 25)

local trackerSubtitle = text(
    trackerPage,
    "Live vehicle positions and directions",
    10, Theme.Muted
)
trackerSubtitle.Position = UDim2.new(0, 16, 0, 37)
trackerSubtitle.Size = UDim2.new(1, -32, 0, 18)

local liveStatus = text(
    trackerPage, "● LIVE", 10, Theme.Accent, true
)
liveStatus.Position = UDim2.new(0, 16, 0, 60)
liveStatus.Size = UDim2.new(0, 120, 0, 22)

local vehicleCount = text(
    trackerPage, "0 vehicles", 10, Theme.Muted
)
vehicleCount.Position = UDim2.new(1, -145, 0, 60)
vehicleCount.Size = UDim2.new(0, 125, 0, 22)
vehicleCount.TextXAlignment = Enum.TextXAlignment.Right

-- TARGET PANEL
local targetPanel = create("Frame", {
    Size = UDim2.new(1, -32, 0, 75),
    Position = UDim2.new(0, 16, 0, 88),
    BackgroundColor3 = Theme.Surface,
    BackgroundTransparency = 0.16,
    BorderSizePixel = 0
}, trackerPage)
round(targetPanel, 7)

local targetTitle = text(
    targetPanel, "SELECTED TARGET", 9, Theme.Muted, true
)
targetTitle.Position = UDim2.new(0, 10, 0, 6)
targetTitle.Size = UDim2.new(1, -20, 0, 16)

local targetName = text(
    targetPanel, "No vehicle selected", 13, Theme.Text, true
)
targetName.Position = UDim2.new(0, 10, 0, 25)
targetName.Size = UDim2.new(1, -20, 0, 20)

local targetDistance = text(
    targetPanel, "Tap a vehicle to track",
    11, Theme.Accent, true
)
targetDistance.Position = UDim2.new(0, 10, 0, 48)
targetDistance.Size = UDim2.new(1, -20, 0, 20)

local listTitle = text(
    trackerPage, "DETECTED VEHICLES", 10, Theme.Muted, true
)
listTitle.Position = UDim2.new(0, 16, 0, 171)
listTitle.Size = UDim2.new(1, -150, 0, 24)

-- Selected vehicle tracking line (screen-space tracer)
local targetTracer = create("Frame", {
    Name = "VEZA_SelectedVehicleLine",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.fromOffset(0, 3),
    BackgroundColor3 = Color3.fromRGB(255, 220, 40),
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 50
}, gui)
round(targetTracer, 3)

local targetTracerDot = create("Frame", {
    Name = "VEZA_SelectedVehicleDot",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(9, 9),
    BackgroundColor3 = Color3.fromRGB(255, 235, 90),
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 51
}, gui)
round(targetTracerDot, 9)

-- Compact waypoint label for the currently selected vehicle.
local vehicleWaypoint = create("Frame", {
    Name = "VEZA_VehicleWaypoint",
    AnchorPoint = Vector2.new(0.5, 1),
    Size = UDim2.fromOffset(190, 28),
    BackgroundColor3 = Color3.fromRGB(10, 18, 24),
    BackgroundTransparency = 0.18,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 60
}, gui)
local waypointStroke = create("UIStroke", {
    Color = Color3.fromRGB(255, 220, 40),
    Thickness = 1,
    Transparency = 0.05
}, vehicleWaypoint)
round(vehicleWaypoint, 2)

local waypointText = text(
    vehicleWaypoint, "VEHICLE  •  -- studs",
    11, Color3.fromRGB(255, 235, 120), true
)
waypointText.Position = UDim2.fromOffset(7, 0)
waypointText.Size = UDim2.new(1, -14, 1, 0)
waypointText.TextXAlignment = Enum.TextXAlignment.Center
waypointText.ZIndex = 61

local vehicleESPToggle = button(
    trackerPage, "CAR ESP: OFF", Theme.Border
)
vehicleESPToggle.Position = UDim2.new(1, -126, 0, 166)
vehicleESPToggle.Size = UDim2.new(0, 110, 0, 27)

local vehicleList = create("ScrollingFrame", {
    Size = UDim2.new(1, -32, 1, -204),
    Position = UDim2.new(0, 16, 0, 196),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.Accent,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y
}, trackerPage)

create("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder
}, vehicleList)

-- Compact-mode selector and dedicated boss list.
local compactTabs = create("Frame", {
    Name = "VEZA_CompactTabs",
    Size = UDim2.new(1, -20, 0, 28),
    Position = UDim2.new(0, 10, 0, 5),
    BackgroundTransparency = 1,
    Visible = false
}, trackerPage)
local compactCarTab = button(compactTabs, "CARS", Theme.Accent)
compactCarTab.Position = UDim2.new(0, 0, 0, 0)
compactCarTab.Size = UDim2.new(0.5, -3, 1, 0)
local compactBossTab = button(compactTabs, "BOSSES", Theme.Border)
compactBossTab.Position = UDim2.new(0.5, 3, 0, 0)
compactBossTab.Size = UDim2.new(0.5, -3, 1, 0)

local bossCount = text(trackerPage, "0 bosses", 10, Theme.Muted, true)
bossCount.Position = UDim2.new(0, 12, 0, 10)
bossCount.Size = UDim2.new(1, -24, 0, 20)
bossCount.Visible = false

local bossList = create("ScrollingFrame", {
    Name = "VEZA_BossList",
    Size = UDim2.new(1, -20, 1, -46),
    Position = UDim2.new(0, 10, 0, 36),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.Accent,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Visible = false
}, trackerPage)
create("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder
}, bossList)

-- Unified minimized results: cars and bosses share one scrollable list.
local compactCombinedList = create("ScrollingFrame", {
    Name = "VEZA_CompactCombinedList",
    Size = UDim2.new(1, -20, 1, -70),
    Position = UDim2.new(0, 10, 0, 60),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.Accent,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Visible = false
}, trackerPage)
create("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder
}, compactCombinedList)
local compactCount = text(trackerPage, "0 cars • 0 bosses", 10, Theme.Muted, true)
compactCount.Position = UDim2.new(0, 12, 0, 36)
compactCount.Size = UDim2.new(1, -24, 0, 20)
compactCount.TextXAlignment = Enum.TextXAlignment.Left
compactCount.Visible = false

-- Wide compact layout: BOSSES on the left, CARS on the right.
local compactBossTitle = text(trackerPage, "BOSSES", 9, Theme.Muted, true)
compactBossTitle.Visible = false
local compactCarTitle = text(trackerPage, "CARS", 9, Theme.Muted, true)
compactCarTitle.Visible = false

local compactBossColumn = create("ScrollingFrame", {
    Name = "VEZA_CompactBossColumn",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.Accent,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Visible = false
}, trackerPage)
create("UIListLayout", {
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder
}, compactBossColumn)

local compactCarColumn = create("ScrollingFrame", {
    Name = "VEZA_CompactCarColumn",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.Accent,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Visible = false
}, trackerPage)
create("UIListLayout", {
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder
}, compactCarColumn)

local function updateCompactModeButtons()
    compactCarTab.BackgroundColor3 = compactMode == "Cars" and Theme.Accent or Theme.Border
    compactBossTab.BackgroundColor3 = compactMode == "Bosses" and Theme.Accent or Theme.Border
    vehicleList.Visible = compactMode == "Cars"
    bossList.Visible = compactMode == "Bosses"
    vehicleCount.Visible = compactMode == "Cars"
    bossCount.Visible = compactMode == "Bosses"
end
compactCarTab.MouseButton1Click:Connect(function()
    compactMode = "Cars"
    updateCompactModeButtons()
end)
compactBossTab.MouseButton1Click:Connect(function()
    compactMode = "Bosses"
    updateCompactModeButtons()
end)

--========================================================
-- PAGE 2: DISTANCE SETTINGS
--========================================================

local settingsPage = registerPage(
    "Distance", "Distance Settings", 2
)

local settingsTitle = text(
    settingsPage, "Distance Settings", 16, Theme.Text, true
)
settingsTitle.Position = UDim2.new(0, 16, 0, 12)
settingsTitle.Size = UDim2.new(1, -32, 0, 25)

local settingsSubtitle = text(
    settingsPage,
    "Configure vehicle detection radius",
    10, Theme.Muted
)
settingsSubtitle.Position = UDim2.new(0, 16, 0, 37)
settingsSubtitle.Size = UDim2.new(1, -32, 0, 20)

local distancePanel = create("Frame", {
    Size = UDim2.new(1, -32, 0, 115),
    Position = UDim2.new(0, 16, 0, 70),
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0
}, settingsPage)
round(distancePanel, 7)

local distanceTitle = text(
    distancePanel, "Maximum Scan Distance",
    12, Theme.Text, true
)
distanceTitle.Position = UDim2.new(0, 12, 0, 10)
distanceTitle.Size = UDim2.new(1, -24, 0, 20)

local distanceValue = text(
    distancePanel, "1000 studs",
    11, Theme.Accent, true
)
distanceValue.Position = UDim2.new(0, 12, 0, 34)
distanceValue.Size = UDim2.new(1, -24, 0, 20)

local sliderBar = create("Frame", {
    Size = UDim2.new(1, -30, 0, 6),
    Position = UDim2.new(0, 15, 0, 77),
    BackgroundColor3 = Theme.Border,
    BorderSizePixel = 0
}, distancePanel)
round(sliderBar, 6)

local sliderFill = create("Frame", {
    Size = UDim2.new(0, 0, 1, 0),
    BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0
}, sliderBar)
round(sliderFill, 6)

local sliderKnob = create("Frame", {
    Size = UDim2.new(0, 15, 0, 15),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0, 0, 0.5, 0),
    BackgroundColor3 = Theme.Text,
    BorderSizePixel = 0
}, sliderBar)
round(sliderKnob, 10)

local MIN_DISTANCE = 100
local MAX_DISTANCE = 5000

local function updateSlider()
    local percent = (
        Settings.MaxDistance - MIN_DISTANCE
    ) / (MAX_DISTANCE - MIN_DISTANCE)

    sliderFill.Size = UDim2.new(percent, 0, 1, 0)
    sliderKnob.Position = UDim2.new(percent, 0, 0.5, 0)

    distanceValue.Text =
        Settings.UnlimitedDistance
        and "Unlimited"
        or (Settings.MaxDistance .. " studs")
end

local draggingSlider = false

local function setSliderFromX(x)
    if Settings.UnlimitedDistance then return end

    local startX = sliderBar.AbsolutePosition.X
    local width = sliderBar.AbsoluteSize.X

    if width <= 0 then return end

    local percent = math.clamp(
        (x - startX) / width, 0, 1
    )

    local value = MIN_DISTANCE
        + percent * (MAX_DISTANCE - MIN_DISTANCE)

    Settings.MaxDistance = math.clamp(
        math.floor(value / 50 + 0.5) * 50,
        MIN_DISTANCE,
        MAX_DISTANCE
    )

    updateSlider()
end

track(sliderBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then

        draggingSlider = true
        setSliderFromX(input.Position.X)
    end
end))

track(UIS.InputChanged:Connect(function(input)
    if draggingSlider and (
        input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    ) then
        setSliderFromX(input.Position.X)
    end
end))

track(UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        draggingSlider = false
    end
end))

-- UNLIMITED TOGGLE
local unlimitedPanel = create("Frame", {
    Size = UDim2.new(1, -32, 0, 52),
    Position = UDim2.new(0, 16, 0, 196),
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0
}, settingsPage)
round(unlimitedPanel, 7)

local unlimitedLabel = text(
    unlimitedPanel, "Unlimited Scan Distance",
    11, Theme.Text, true
)
unlimitedLabel.Position = UDim2.new(0, 12, 0, 10)
unlimitedLabel.Size = UDim2.new(1, -95, 0, 30)

local unlimitedButton = button(
    unlimitedPanel, "OFF", Theme.Border
)
unlimitedButton.Position = UDim2.new(1, -66, 0, 12)
unlimitedButton.Size = UDim2.new(0, 54, 0, 28)

local function updateUnlimited()
    unlimitedButton.Text =
        Settings.UnlimitedDistance and "ON" or "OFF"

    unlimitedButton.BackgroundColor3 =
        Settings.UnlimitedDistance
        and Theme.Accent
        or Theme.Border

    updateSlider()
end

unlimitedButton.MouseButton1Click:Connect(function()
    Settings.UnlimitedDistance =
        not Settings.UnlimitedDistance

    updateUnlimited()
    saveConfig()
end)

local note = text(
    settingsPage,
    "Only vehicles replicated to your client can be detected.",
    10, Theme.Muted
)
note.Position = UDim2.new(0, 16, 0, 263)
note.Size = UDim2.new(1, -32, 0, 35)
note.TextWrapped = true

--========================================================
-- PAGE 3: PREFERENCES + REMEMBER SETTINGS
--========================================================

local preferencesPage = registerPage(
    "Preferences", "Preferences", 3
)

local preferencesTitle = text(
    preferencesPage, "Preferences", 16, Theme.Text, true
)
preferencesTitle.Position = UDim2.new(0, 16, 0, 12)
preferencesTitle.Size = UDim2.new(1, -32, 0, 25)

local preferencesSubtitle = text(
    preferencesPage,
    "Save settings and configure Hush camera zoom",
    10, Theme.Muted
)
preferencesSubtitle.Position = UDim2.new(0, 16, 0, 37)
preferencesSubtitle.Size = UDim2.new(1, -32, 0, 20)

local rememberPanel = create("Frame", {
    Size = UDim2.new(1, -32, 0, 55),
    Position = UDim2.new(0, 16, 0, 70),
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0
}, preferencesPage)
round(rememberPanel, 7)

local rememberLabel = text(
    rememberPanel, "Remember Settings", 12, Theme.Text, true
)
rememberLabel.Position = UDim2.new(0, 12, 0, 7)
rememberLabel.Size = UDim2.new(1, -105, 0, 20)

local rememberHint = text(
    rememberPanel, "Restore options next time you execute", 9, Theme.Muted
)
rememberHint.Position = UDim2.new(0, 12, 0, 29)
rememberHint.Size = UDim2.new(1, -105, 0, 16)

local rememberButton = button(
    rememberPanel, RememberSettings and "ON" or "OFF",
    RememberSettings and Theme.Accent or Theme.Border
)
rememberButton.Position = UDim2.new(1, -66, 0, 13)
rememberButton.Size = UDim2.new(0, 54, 0, 29)

local zoomPanel = create("Frame", {
    Size = UDim2.new(1, -32, 0, 116),
    Position = UDim2.new(0, 16, 0, 137),
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0
}, preferencesPage)
round(zoomPanel, 7)

local zoomTitle = text(
    zoomPanel, "Hush Unlimited Camera Zoom", 12, Theme.Text, true
)
zoomTitle.Position = UDim2.new(0, 12, 0, 8)
zoomTitle.Size = UDim2.new(1, -24, 0, 20)

local zoomHint = text(
    zoomPanel, "Distance in studs (1–1000)", 9, Theme.Muted
)
zoomHint.Position = UDim2.new(0, 12, 0, 31)
zoomHint.Size = UDim2.new(1, -24, 0, 16)

local zoomInput = create("TextBox", {
    Size = UDim2.new(0, 95, 0, 30),
    Position = UDim2.new(0, 12, 0, 61),
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    Text = tostring(ZoomDistance),
    PlaceholderText = "300",
    TextColor3 = Theme.Text,
    PlaceholderColor3 = Theme.Muted,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    ClearTextOnFocus = false
}, zoomPanel)
round(zoomInput, 5)

local zoomToggle = button(
    zoomPanel, ZoomEnabled and "ZOOM: ON" or "ZOOM: OFF",
    ZoomEnabled and Theme.Accent or Theme.Border
)
zoomToggle.Position = UDim2.new(1, -112, 0, 61)
zoomToggle.Size = UDim2.new(0, 100, 0, 30)

local saveButton = button(
    preferencesPage, "SAVE SETTINGS NOW", Theme.Accent
)
saveButton.Position = UDim2.new(0, 16, 0, 267)
saveButton.Size = UDim2.new(0.5, -22, 0, 34)

local resetButton = button(
    preferencesPage, "RESET DEFAULTS", Theme.Border
)
resetButton.Position = UDim2.new(0.5, 6, 0, 267)
resetButton.Size = UDim2.new(0.5, -22, 0, 34)

local resetVehicleListsButton = button(preferencesPage, "RESET CAR FAVORITES / IGNORE", Theme.Border)
resetVehicleListsButton.Position = UDim2.new(0, 16, 0, 307)
resetVehicleListsButton.Size = UDim2.new(1, -32, 0, 30)
local preferenceStatus = text(
    preferencesPage, "Status: waiting", 9, Theme.Muted
)
preferenceStatus.Position = UDim2.new(0, 16, 0, 337)
preferenceStatus.Size = UDim2.new(1, -32, 0, 20)

local refreshIgnoreList

resetVehicleListsButton.MouseButton1Click:Connect(function()
    favoriteVehicles = {}
    ignoredVehicles = {}
    saveVehicleLists()
    if scanVehicles then scanVehicles() end
    preferenceStatus.Text = "Status: car list restored to normal"
    refreshIgnoreList()
end)

-- Dedicated Ignore List page so ignored vehicle types can be restored anytime.
local ignoreListPage = registerPage("Ignore List", "Ignore List", 4)
local ignoreListTitle = text(ignoreListPage, "Ignored Vehicles", 16, Theme.Text, true)
ignoreListTitle.Position = UDim2.new(0, 16, 0, 12)
ignoreListTitle.Size = UDim2.new(1, -32, 0, 25)
local ignoreListSubtitle = text(ignoreListPage, "Vehicles here are hidden from minimized CARS results", 10, Theme.Muted)
ignoreListSubtitle.Position = UDim2.new(0, 16, 0, 38)
ignoreListSubtitle.Size = UDim2.new(1, -32, 0, 20)
local ignoreListStatus = text(ignoreListPage, "0 ignored vehicles", 10, Theme.Accent, true)
ignoreListStatus.Position = UDim2.new(0, 16, 0, 64)
ignoreListStatus.Size = UDim2.new(1, -32, 0, 20)
local ignoreListContainer = create("ScrollingFrame", {
    Name = "IgnoreListEntries",
    Size = UDim2.new(1, -32, 1, -104),
    Position = UDim2.new(0, 16, 0, 92),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.Accent,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y
}, ignoreListPage)
create("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, ignoreListContainer)

refreshIgnoreList = function()
    for _, child in ipairs(ignoreListContainer:GetChildren()) do
        if child:IsA("TextButton") or child.Name == "IgnoreEmptyLabel" then child:Destroy() end
    end
    local names = {}
    for name in pairs(ignoredVehicles) do table.insert(names, name) end
    table.sort(names)
    ignoreListStatus.Text = tostring(#names) .. " ignored vehicle types"
    if #names == 0 then
        local empty = text(ignoreListContainer, "Your Ignore List is empty", 11, Theme.Muted)
        empty.Name = "IgnoreEmptyLabel"
        empty.Size = UDim2.new(1, -6, 0, 34)
        empty.LayoutOrder = 1
        return
    end
    for index, name in ipairs(names) do
        local row = button(ignoreListContainer, "", Theme.Surface)
        row.Size = UDim2.new(1, -6, 0, 42)
        row.LayoutOrder = index
        row.Text = ""
        local label = text(row, name, 11, Theme.Text, true)
        label.Position = UDim2.new(0, 10, 0, 0)
        label.Size = UDim2.new(1, -100, 1, 0)
        local restore = button(row, "RESTORE", Theme.Accent)
        restore.Position = UDim2.new(1, -84, 0, 7)
        restore.Size = UDim2.new(0, 76, 0, 28)
        restore.TextSize = 9
        restore.MouseButton1Click:Connect(function()
            ignoredVehicles[name] = nil
            saveVehicleLists()
            refreshIgnoreList()
            if scanVehicles then scanVehicles() end
        end)
    end
end
refreshIgnoreList()

local function updateRememberUI()
    rememberButton.Text = RememberSettings and "ON" or "OFF"
    rememberButton.BackgroundColor3 =
        RememberSettings and Theme.Accent or Theme.Border
end

local function updateZoomUI()
    zoomToggle.Text = ZoomEnabled and "ZOOM: ON" or "ZOOM: OFF"
    zoomToggle.BackgroundColor3 =
        ZoomEnabled and Theme.Accent or Theme.Border
    zoomInput.Text = tostring(ZoomDistance)
end

rememberButton.MouseButton1Click:Connect(function()
    RememberSettings = not RememberSettings
    updateRememberUI()

    if RememberSettings then
        local ok = saveConfig()
        preferenceStatus.Text = ok
            and "Status: remembering settings"
            or "Status: file API unavailable"
    else
        if canUseFileAPI() then
            ensureConfigFolder()
            pcall(function()
                writefile(CONFIG_FILE, HttpService:JSONEncode({
                    RememberSettings = false
                }))
            end)
        end
        preferenceStatus.Text = "Status: remember is OFF"
    end
end)

zoomToggle.MouseButton1Click:Connect(function()
    ZoomEnabled = not ZoomEnabled
    if ZoomEnabled then
        applyCameraZoom()
        preferenceStatus.Text = "Status: zoom patch enabled"
    else
        restoreCameraZoom()
        preferenceStatus.Text = "Status: zoom patch disabled"
    end
    updateZoomUI()
    saveConfig()
end)

zoomInput.FocusLost:Connect(function()
    local value = tonumber(zoomInput.Text)
    if not value then
        zoomInput.Text = tostring(ZoomDistance)
        preferenceStatus.Text = "Status: enter a valid number"
        return
    end

    ZoomDistance = math.clamp(math.floor(value), 1, 1000)
    zoomInput.Text = tostring(ZoomDistance)
    if ZoomEnabled then
        applyCameraZoom()
    end
    preferenceStatus.Text = "Status: zoom distance set to "
        .. ZoomDistance .. " (scroll out to maximum)"
    saveConfig()
end)

saveButton.MouseButton1Click:Connect(function()
    local ok = saveConfig()
    preferenceStatus.Text = ok
        and "Status: settings saved to VEZA_GUI_settings.json"
        or "Status: save failed — executor file API unavailable"
end)

resetButton.MouseButton1Click:Connect(function()
    Settings.MaxDistance = 1000
    Settings.UnlimitedDistance = false
    zombieESPEnabled = true
    vehicleESPEnabled = true
    militaryMapEnabled = true
    updateMilitaryToggle()
    ZoomEnabled = true
    ZoomDistance = 300

    updateSlider()
    updateUnlimited()
    updateZombieToggle()
    updateVehicleToggle()
    updateZoomUI()
    applyCameraZoom()
    saveConfig()

    preferenceStatus.Text = "Status: defaults restored"
end)

--========================================================
-- PAGE 4: ZOMBIE ESP
--========================================================

local zombiePage = registerPage(
    "ZombieESP", "Zombie ESP", 4
)

local zombieTitle = text(
    zombiePage, "Zombie ESP", 16, Theme.Text, true
)
zombieTitle.Position = UDim2.new(0, 16, 0, 12)
zombieTitle.Size = UDim2.new(1, -32, 0, 25)

local zombieSubtitle = text(
    zombiePage,
    "Highlight zombies around the map",
    10, Theme.Muted
)
zombieSubtitle.Position = UDim2.new(0, 16, 0, 37)
zombieSubtitle.Size = UDim2.new(1, -32, 0, 20)

local zombiePanel = create("Frame", {
    Size = UDim2.new(1, -32, 0, 85),
    Position = UDim2.new(0, 16, 0, 70),
    BackgroundColor3 = Theme.Surface,
    BackgroundTransparency = 0.16,
    BorderSizePixel = 0
}, zombiePage)
round(zombiePanel, 7)

local zombieOption = text(
    zombiePanel, "Zombie Highlight",
    12, Theme.Text, true
)
zombieOption.Position = UDim2.new(0, 12, 0, 12)
zombieOption.Size = UDim2.new(0.55, 0, 0, 22)

local zombieDescription = text(
    zombiePanel,
    "Glow visible on detected zombies",
    9, Theme.Muted
)
zombieDescription.Position = UDim2.new(0, 12, 0, 37)
zombieDescription.Size = UDim2.new(0.65, 0, 0, 20)

local zombieToggle = button(
    zombiePanel, "ESP: OFF", Theme.Border
)
zombieToggle.Position = UDim2.new(1, -92, 0, 24)
zombieToggle.Size = UDim2.new(0, 78, 0, 32)

local zombieStatusPanel = create("Frame", {
    Size = UDim2.new(1, -32, 0, 65),
    Position = UDim2.new(0, 16, 0, 166),
    BackgroundColor3 = Theme.Surface,
    BackgroundTransparency = 0.16,
    BorderSizePixel = 0
}, zombiePage)
round(zombieStatusPanel, 7)

local zombieStatus = text(
    zombieStatusPanel,
    "STATUS: DISABLED",
    11, Theme.Muted, true
)
zombieStatus.Position = UDim2.new(0, 12, 0, 8)
zombieStatus.Size = UDim2.new(1, -24, 0, 20)

local zombieCount = text(
    zombieStatusPanel,
    "ZOMBIES HIGHLIGHTED: 0",
    10, Theme.Text
)
zombieCount.Position = UDim2.new(0, 12, 0, 32)
zombieCount.Size = UDim2.new(1, -24, 0, 20)

local zombieInfo = text(
    zombiePage,
    "Client-side highlight. Newly replicated zombies are detected automatically.",
    10, Theme.Muted
)
zombieInfo.Position = UDim2.new(0, 16, 0, 244)
zombieInfo.Size = UDim2.new(1, -32, 0, 42)
zombieInfo.TextWrapped = true

--========================================================
-- PAGE 5: MILITARY MAP HIGHLIGHT
--========================================================

local militaryPage = registerPage(
    "MilitaryMap", "Military Map", 5
)

local militaryTitle = text(
    militaryPage, "Military Location", 16, Theme.Text, true
)
militaryTitle.Position = UDim2.new(0, 16, 0, 12)
militaryTitle.Size = UDim2.new(1, -32, 0, 25)

local militarySubtitle = text(
    militaryPage,
    "Highlight selected military base zones on the Hush map",
    10, Theme.Muted
)
militarySubtitle.Position = UDim2.new(0, 16, 0, 37)
militarySubtitle.Size = UDim2.new(1, -32, 0, 20)

local militaryPanel = create("Frame", {
    Size = UDim2.new(1, -32, 0, 90),
    Position = UDim2.new(0, 16, 0, 72),
    BackgroundColor3 = Theme.Surface,
    BackgroundTransparency = 0.16,
    BorderSizePixel = 0
}, militaryPage)
round(militaryPanel, 7)

local militaryOption = text(
    militaryPanel, "Military Zone Highlight",
    12, Theme.Text, true
)
militaryOption.Position = UDim2.new(0, 12, 0, 12)
militaryOption.Size = UDim2.new(0.62, 0, 0, 22)

local militaryDescription = text(
    militaryPanel,
    "Yellow outline on selected map squares",
    9, Theme.Muted
)
militaryDescription.Position = UDim2.new(0, 12, 0, 39)
militaryDescription.Size = UDim2.new(0.68, 0, 0, 20)

local militaryToggle = button(
    militaryPanel, "MAP ESP: OFF", Theme.Border
)
militaryToggle.Position = UDim2.new(1, -102, 0, 27)
militaryToggle.Size = UDim2.new(0, 88, 0, 32)

local militaryStatus = text(
    militaryPage, "STATUS: DISABLED",
    10, Theme.Muted, true
)
militaryStatus.Position = UDim2.new(0, 16, 0, 178)
militaryStatus.Size = UDim2.new(1, -32, 0, 22)

local militaryInfo = text(
    militaryPage,
    "Highlights the eight selected military map tiles. Requires HushMap to be loaded.",
    10, Theme.Muted
)
militaryInfo.Position = UDim2.new(0, 16, 0, 208)
militaryInfo.Size = UDim2.new(1, -32, 0, 48)
militaryInfo.TextWrapped = true

--========================================================
-- PAGE 6: ENVIRONMENT (FORCE DAY + NO SNOW)
--========================================================

local environmentPage = registerPage(
    "Environment", "Environment", 6
)

local environmentTitle = text(
    environmentPage, "Environment Override", 16, Theme.Text, true
)
environmentTitle.Position = UDim2.new(0, 16, 0, 12)
environmentTitle.Size = UDim2.new(1, -32, 0, 25)

local environmentSubtitle = text(
    environmentPage,
    "Local visual time and weather preset",
    10, Theme.Muted
)
environmentSubtitle.Position = UDim2.new(0, 16, 0, 37)
environmentSubtitle.Size = UDim2.new(1, -32, 0, 20)

local environmentPanel = create("Frame", {
    Size = UDim2.new(1, -32, 0, 94),
    Position = UDim2.new(0, 16, 0, 72),
    BackgroundColor3 = Theme.Surface,
    BackgroundTransparency = 0.16,
    BorderSizePixel = 0
}, environmentPage)
round(environmentPanel, 7)

local environmentOption = text(
    environmentPanel, "Force Day + No Snow",
    12, Theme.Text, true
)
environmentOption.Position = UDim2.new(0, 12, 0, 10)
environmentOption.Size = UDim2.new(0.62, 0, 0, 22)

local environmentDescription = text(
    environmentPanel,
    "Sets local Raid preset to Day / Clear",
    9, Theme.Muted
)
environmentDescription.Position = UDim2.new(0, 12, 0, 35)
environmentDescription.Size = UDim2.new(0.68, 0, 0, 20)

local environmentToggle = button(
    environmentPanel, "ON", Theme.Accent
)
environmentToggle.Position = UDim2.new(1, -76, 0, 27)
environmentToggle.Size = UDim2.new(0, 62, 0, 32)

local environmentStatus = text(
    environmentPage, "STATUS: WAITING FOR ATMOSPHERE",
    10, Theme.Muted, true
)
environmentStatus.Position = UDim2.new(0, 16, 0, 182)
environmentStatus.Size = UDim2.new(1, -32, 0, 22)

local environmentInfo = text(
    environmentPage,
    "Client-side only. Does not change server time or weather. Requires the Atmosphere controller to be loaded.",
    10, Theme.Muted
)
environmentInfo.Position = UDim2.new(0, 16, 0, 211)
environmentInfo.Size = UDim2.new(1, -32, 0, 48)
environmentInfo.TextWrapped = true

-- The override is enabled by default whenever VEZA starts.
local forceDayNoSnowEnabled = true
local atmosphereController = nil

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
        environmentStatus.Text = "STATUS: " .. tostring(reason)
        environmentStatus.TextColor3 = Theme.Muted
        return false
    end

    local ok, result = pcall(function()
        controller.setOverride("Raid", "Day", "Clear", 0)
    end)

    if ok then
        environmentStatus.Text = "STATUS: FORCE DAY + NO SNOW ACTIVE"
        environmentStatus.TextColor3 = Theme.Accent
        return true
    end

    environmentStatus.Text = "STATUS: OVERRIDE FAILED"
    environmentStatus.TextColor3 = Theme.Red
    warn("[VEZA] Force Day / No Snow failed: " .. tostring(result))
    return false
end

local function restoreEnvironment()
    local controller = atmosphereController
    if not controller then
        controller = findAtmosphereController()
    end

    if not controller then
        environmentStatus.Text = "STATUS: CONTROLLER NOT FOUND"
        environmentStatus.TextColor3 = Theme.Muted
        return false
    end

    local ok, result = pcall(function()
        controller.clearOverride(0)
    end)

    if ok then
        environmentStatus.Text = "STATUS: GAME DEFAULT RESTORED"
        environmentStatus.TextColor3 = Theme.Muted
        return true
    end

    environmentStatus.Text = "STATUS: RESTORE FAILED"
    environmentStatus.TextColor3 = Theme.Red
    warn("[VEZA] Environment restore failed: " .. tostring(result))
    return false
end

local function updateEnvironmentToggle()
    environmentToggle.Text = forceDayNoSnowEnabled and "ON" or "OFF"
    environmentToggle.BackgroundColor3 =
        forceDayNoSnowEnabled and Theme.Accent or Theme.Border
end

environmentToggle.MouseButton1Click:Connect(function()
    forceDayNoSnowEnabled = not forceDayNoSnowEnabled
    updateEnvironmentToggle()

    if forceDayNoSnowEnabled then
        applyDayNoSnow()
    else
        restoreEnvironment()
    end
end)

--========================================================
-- ZOMBIE ESP ENGINE
--========================================================


local function getZombieFolder()
    local hushLocal = workspace:FindFirstChild("HushLocal")

    if not hushLocal then
        return nil
    end

    return hushLocal:FindFirstChild("Zombies")
end

local function clearZombieESP()
    for model, highlight in pairs(zombieHighlights) do
        if highlight then
            pcall(function()
                highlight:Destroy()
            end)
        end

        zombieHighlights[model] = nil
    end

    zombieCount.Text = "ZOMBIES HIGHLIGHTED: 0"
end

local function addZombieHighlight(model)
    if not model or not model.Parent then
        return false
    end

    if not (
        model:IsA("Model")
        or model:IsA("BasePart")
    ) then
        return false
    end

    if zombieHighlights[model] then
        return true
    end

    local highlight = Instance.new("Highlight")
    highlight.Name = "VEZA_ZombieESP"
    highlight.Adornee = model

    highlight.FillColor = Theme.ZombieFill
    highlight.OutlineColor = Theme.ZombieOutline

    highlight.FillTransparency = 0.78
    highlight.OutlineTransparency = 0.05

    -- Visible only when not blocked by geometry
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded

    highlight.Parent = model

    zombieHighlights[model] = highlight

    return true
end

local function scanZombies()
    if not zombieESPEnabled then
        return
    end

    local folder = getZombieFolder()

    if not folder then
        zombieStatus.Text = "STATUS: WAITING FOR ZOMBIES"
        zombieStatus.TextColor3 = Theme.Muted
        return
    end

    local count = 0
    local present = {}

    for _, model in ipairs(folder:GetChildren()) do
        if addZombieHighlight(model) then
            present[model] = true
            count += 1
        end
    end

    -- Remove highlights from despawned models
    for model, highlight in pairs(zombieHighlights) do
        if not present[model] then
            if highlight then
                highlight:Destroy()
            end

            zombieHighlights[model] = nil
        end
    end

    zombieStatus.Text = "STATUS: ESP ACTIVE"
    zombieStatus.TextColor3 = Theme.Accent

    zombieCount.Text =
        "ZOMBIES HIGHLIGHTED: " .. count
end

updateZombieToggle = function()
    if zombieESPEnabled then
        zombieToggle.Text = "ESP: ON"
        zombieToggle.BackgroundColor3 = Theme.Accent

        zombieStatus.Text = "STATUS: ESP ACTIVE"
        zombieStatus.TextColor3 = Theme.Accent

        scanZombies()
    else
        zombieToggle.Text = "ESP: OFF"
        zombieToggle.BackgroundColor3 = Theme.Border

        zombieStatus.Text = "STATUS: DISABLED"
        zombieStatus.TextColor3 = Theme.Muted

        clearZombieESP()
    end
end

if _G.VEZA_LoadZombieESP == true then
    zombieESPEnabled = true
    _G.VEZA_LoadZombieESP = nil
end

--========================================================
-- MILITARY MAP HIGHLIGHT ENGINE
--========================================================

local militaryMapTargets = {}
local militaryMapOriginals = {}

local function getMilitaryMapTargets()
    local hushMap = PlayerGui:FindFirstChild("HushMap")
    local root = hushMap and hushMap:FindFirstChild("Root")
    local mapPanel = root and root:FindFirstChild("MapPanel")
    local content = mapPanel and mapPanel:FindFirstChild("Content")
    local sheetHolder = content and content:FindFirstChild("SheetHolder")
    local zoomLayer = sheetHolder and sheetHolder:FindFirstChild("ZoomLayer")
    local sheet = zoomLayer and zoomLayer:FindFirstChild("Sheet")
    local area = sheet and sheet:FindFirstChild("Area")
    local ground = area and area:FindFirstChild("Ground")

    if not ground then
        return {}
    end

    local children = ground:GetChildren()

    -- Ground is the parent container, not a single military tile.
    -- Highlight the eight specific map objects supplied by the user.
    local targets = {
        children[28],
        ground:FindFirstChild("Biome_military"),
        children[4],
        children[19],
        children[12],
        children[23],
        children[24],
        children[7],
    }

    local valid = {}
    local seen = {}

    local function addGuiObject(object)
        if object and object:IsA("GuiObject") and not seen[object] then
            seen[object] = true
            table.insert(valid, object)
        end
    end

    for _, target in ipairs(targets) do
        if target then
            if target:IsA("GuiObject") then
                -- Normal map tile (Frame / ImageLabel / ImageButton).
                addGuiObject(target)
            else
                -- Some map zones are containers; highlight their GUI descendants.
                for _, descendant in ipairs(target:GetDescendants()) do
                    addGuiObject(descendant)
                end
            end
        end
    end

    return valid
end

local function clearMilitaryMapHighlight()
    for object, record in pairs(militaryMapOriginals) do
        if object and object.Parent then
            pcall(function()
                if record.stroke then
                    record.stroke:Destroy()
                end
                object.BackgroundColor3 = record.color
                object.BackgroundTransparency = record.transparency
                if record.hasImageColor then
                    object.ImageColor3 = record.imageColor
                end
            end)
        end
        militaryMapOriginals[object] = nil
    end
    militaryMapTargets = {}
end

local function scanMilitaryMap()
    local targets = getMilitaryMapTargets()
    local present = {}

    for _, object in ipairs(targets) do
        present[object] = true
        if not militaryMapOriginals[object] then
            local stroke = Instance.new("UIStroke")
            stroke.Name = "VEZA_MilitaryMapStroke"
            stroke.Color = Color3.fromRGB(255, 220, 40)
            stroke.Thickness = 2
            stroke.Transparency = 0
            stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            stroke.Parent = object

            local originalImageColor
            local hasImageColor = object:IsA("ImageLabel")
                or object:IsA("ImageButton")
            if hasImageColor then
                originalImageColor = object.ImageColor3
            end

            militaryMapOriginals[object] = {
                stroke = stroke,
                color = object.BackgroundColor3,
                transparency = object.BackgroundTransparency,
                imageColor = originalImageColor,
                hasImageColor = hasImageColor,
            }

            object.BackgroundColor3 = Color3.fromRGB(255, 215, 45)
            object.BackgroundTransparency = math.min(
                object.BackgroundTransparency, 0.55
            )
            if hasImageColor then
                object.ImageColor3 = Color3.fromRGB(255, 225, 95)
            end
        end
    end

    for object, record in pairs(militaryMapOriginals) do
        if not present[object] then
            if object and object.Parent then
                pcall(function()
                    if record.stroke then record.stroke:Destroy() end
                    object.BackgroundColor3 = record.color
                    object.BackgroundTransparency = record.transparency
                    if record.hasImageColor then
                        object.ImageColor3 = record.imageColor
                    end
                end)
            end
            militaryMapOriginals[object] = nil
        end
    end

    militaryMapTargets = targets
    militaryStatus.Text = "STATUS: ACTIVE • " .. tostring(#targets) .. " MAP OBJECTS"
    militaryStatus.TextColor3 = Theme.Accent
end

local function disableMilitaryMap()
    clearMilitaryMapHighlight()
    militaryStatus.Text = "STATUS: DISABLED"
    militaryStatus.TextColor3 = Theme.Muted
end

updateMilitaryToggle = function()
    if militaryMapEnabled then
        militaryToggle.Text = "MAP ESP: ON"
        militaryToggle.BackgroundColor3 = Color3.fromRGB(190, 145, 25)
        scanMilitaryMap()
        if #militaryMapTargets == 0 then
            militaryStatus.Text = "STATUS: HUSH MAP NOT READY"
            militaryStatus.TextColor3 = Theme.Red
        end
    else
        militaryToggle.Text = "MAP ESP: OFF"
        militaryToggle.BackgroundColor3 = Theme.Border
        disableMilitaryMap()
    end
end

if _G.VEZA_LoadMilitaryMap == true then
    militaryMapEnabled = true
    _G.VEZA_LoadMilitaryMap = nil
end

militaryToggle.MouseButton1Click:Connect(function()
    militaryMapEnabled = not militaryMapEnabled
    updateMilitaryToggle()
    saveConfig()
end)

zombieToggle.MouseButton1Click:Connect(function()
    zombieESPEnabled = not zombieESPEnabled
    updateZombieToggle()
    saveConfig()
end)

--========================================================
-- VEHICLE TRACKER ENGINE
--========================================================

local function getVehicleFolder()
    local raid = workspace:FindFirstChild("Raid")
    return raid and raid:FindFirstChild("Vehicles")
end

local vehicleHighlights = {}

local function clearVehicleESP()
    for model, highlight in pairs(vehicleHighlights) do
        if highlight then
            pcall(function() highlight:Destroy() end)
        end
        vehicleHighlights[model] = nil
    end
end

local function addVehicleHighlight(model)
    if not model or not model.Parent then return false end
    if not (model:IsA("Model") or model:IsA("BasePart")) then
        return false
    end
    if vehicleHighlights[model] then return true end

    local highlight = Instance.new("Highlight")
    highlight.Name = "VEZA_VehicleESP"
    highlight.Adornee = model
    highlight.FillColor = Color3.fromRGB(255, 220, 40)
    highlight.OutlineColor = Color3.fromRGB(255, 245, 150)
    highlight.FillTransparency = 0.78
    highlight.OutlineTransparency = 0.05
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded
    highlight.Parent = model

    vehicleHighlights[model] = highlight
    return true
end

local function scanVehicleESP()
    if not vehicleESPEnabled then return end
    local folder = getVehicleFolder()
    if not folder then
        clearVehicleESP()
        return
    end

    local present = {}
    for _, model in ipairs(folder:GetChildren()) do
        if addVehicleHighlight(model) then
            present[model] = true
        end
    end

    for model, highlight in pairs(vehicleHighlights) do
        if not present[model] or not model.Parent then
            if highlight then pcall(function() highlight:Destroy() end) end
            vehicleHighlights[model] = nil
        end
    end
end

updateVehicleToggle = function()
    vehicleESPToggle.Text = vehicleESPEnabled and "CAR ESP: ON" or "CAR ESP: OFF"
    vehicleESPToggle.BackgroundColor3 = vehicleESPEnabled
        and Color3.fromRGB(205, 170, 25) or Theme.Border

    if vehicleESPEnabled then
        scanVehicleESP()
    else
        clearVehicleESP()
    end
end

vehicleESPToggle.MouseButton1Click:Connect(function()
    vehicleESPEnabled = not vehicleESPEnabled
    updateVehicleToggle()
    saveConfig()
end)

if _G.VEZA_LoadVehicleESP == true then
    vehicleESPEnabled = true
end
_G.VEZA_LoadVehicleESP = nil

local function getRoot()
    local character = Player.Character

    return character
        and character:FindFirstChild("HumanoidRootPart")
end

local function getVehiclePosition(model)
    if not model or not model.Parent then
        return nil
    end

    local chassis = model:FindFirstChild("Chassis")

    if chassis and chassis:IsA("BasePart") then
        return chassis.Position
    end

    if model:IsA("BasePart") then
        return model.Position
    end

    if model:IsA("Model") then
        local ok, result = pcall(function()
            return model:GetPivot().Position
        end)

        if ok then
            return result
        end
    end

    return nil
end

local function getTrackingInfo(model)
    local root = getRoot()
    local position = getVehiclePosition(model)

    if not root or not position then
        return nil, "?", "Unknown"
    end

    local difference = position - root.Position
    local distance = difference.Magnitude

    local flat = Vector3.new(
        difference.X, 0, difference.Z
    )

    if flat.Magnitude < 0.1 then
        return distance, "•", "Here"
    end

    local localDirection =
        root.CFrame:VectorToObjectSpace(flat.Unit)

    local angle = math.deg(math.atan2(
        localDirection.X,
        -localDirection.Z
    ))

    if angle >= -22.5 and angle < 22.5 then
        return distance, "↑", "Front"
    elseif angle >= 22.5 and angle < 67.5 then
        return distance, "↗", "Front Right"
    elseif angle >= 67.5 and angle < 112.5 then
        return distance, "→", "Right"
    elseif angle >= 112.5 and angle < 157.5 then
        return distance, "↘", "Back Right"
    elseif angle >= 157.5 or angle < -157.5 then
        return distance, "↓", "Behind"
    elseif angle >= -157.5 and angle < -112.5 then
        return distance, "↙", "Back Left"
    elseif angle >= -112.5 and angle < -67.5 then
        return distance, "←", "Left"
    else
        return distance, "↖", "Front Left"
    end
end

local function formatDistance(distance)
    if not distance then return "N/A" end

    return string.format("%.0f studs", distance)
end

local function isInRange(distance)
    if Settings.UnlimitedDistance then
        return true
    end

    return distance ~= nil
        and distance <= Settings.MaxDistance
end

local function clearVehicleRows()
    for _, parent in ipairs({vehicleList, compactCombinedList, compactCarColumn}) do
        for _, child in ipairs(parent:GetChildren()) do
            if child.Name == "VehicleRow" or child.Name == "EmptyLabel" then child:Destroy() end
        end
    end
    vehicleRows = {}
end

local function createVehicleRow(data, order)
    local key = data.name
    local isFavorite = favoriteVehicles[key] == true
    local isIgnored = ignoredVehicles[key] == true

    local row = button(minimized and compactCarColumn or vehicleList, "", isIgnored and Color3.fromRGB(45, 35, 35) or Theme.Surface)
    row.Name = "VehicleRow"
    row.Size = UDim2.new(1, -3, 0, minimized and 30 or 43)
    row.LayoutOrder = order
    row.Text = ""

    local nameLabel = text(row, (isFavorite and "★ " or "") .. data.name .. (isIgnored and "  [IGNORED]" or ""), 11, isIgnored and Theme.Muted or Theme.Text, true)
    nameLabel.Position = UDim2.new(0, 8, 0, minimized and 1 or 5)
    nameLabel.Size = UDim2.new(0.39, -4, 1, minimized and -2 or -10)

    local infoLabel = text(row, "...", 9, Theme.Accent, true)
    infoLabel.Position = UDim2.new(0.40, 0, 0, minimized and 1 or 5)
    infoLabel.Size = UDim2.new(0.27, 0, 1, minimized and -2 or -10)
    infoLabel.TextXAlignment = Enum.TextXAlignment.Right

    local favoriteButton = button(row, isFavorite and "★" or "☆", isFavorite and Color3.fromRGB(145, 110, 25) or Theme.Border)
    favoriteButton.Position = UDim2.new(1, -66, 0, 7)
    favoriteButton.Size = UDim2.new(0, 28, 0, 29)
    favoriteButton.TextSize = 15
    local ignoreButton = button(row, isIgnored and "↶" or "⊘", isIgnored and Theme.Accent or Theme.Border)
    ignoreButton.Position = UDim2.new(1, -34, 0, 7)
    ignoreButton.Size = UDim2.new(0, 28, 0, 29)
    ignoreButton.TextSize = 14

    vehicleRows[data.model] = {button = row, nameLabel = nameLabel, infoLabel = infoLabel, name = data.name}

    row.MouseButton1Click:Connect(function()
        if ignoredVehicles[key] then return end
        if selectedVehicle == data.model then selectedVehicle = nil else selectedVehicle = data.model end
    end)
    favoriteButton.MouseButton1Click:Connect(function()
        favoriteVehicles[key] = not favoriteVehicles[key] or nil
        saveVehicleLists()
        scanVehicles()
    end)
    ignoreButton.MouseButton1Click:Connect(function()
        ignoredVehicles[key] = not ignoredVehicles[key] or nil
        if ignoredVehicles[key] and selectedVehicle == data.model then
            selectedVehicle = nil
        end
        saveVehicleLists()
        refreshIgnoreList()
        scanVehicles()
        updateTracking()
    end)
end

local function renderVehicles()
    clearVehicleRows()
    compactCount.Text = string.format("%d cars  •  %d bosses", #vehicles, #bosses)

    for index, data in ipairs(vehicles) do
        createVehicleRow(data, index)
    end

    if #vehicles == 0 then
        local empty = text(
            minimized and compactCarColumn or vehicleList,
            "No vehicles within scan range",
            11, Theme.Muted
        )

        empty.Name = "EmptyLabel"
        empty.Size = UDim2.new(1, 0, 0, 35)
        empty.TextXAlignment = Enum.TextXAlignment.Center
    end

    local favorites, ignored = 0, 0
    for _, data in ipairs(vehicles) do
        if favoriteVehicles[data.name] then favorites += 1 end
        if ignoredVehicles[data.name] then ignored += 1 end
    end
    vehicleCount.Text = string.format("%d cars  •  ★ %d  •  ignored %d", #vehicles, favorites, ignored)
end

scanVehicles = function()
    if not running then return end

    local folder = getVehicleFolder()

    if not folder then
        vehicles = {}

        liveStatus.Text = "● WAITING FOR RAID"
        liveStatus.TextColor3 = Theme.Muted

        renderVehicles()
        return
    end

    local results = {}

    for _, model in ipairs(folder:GetChildren()) do
        local vehType = model:GetAttribute("VehType")
        local name = model.Name

        if type(vehType) == "string" and vehType ~= "" then
            name = vehType
        end

        local distance = getTrackingInfo(model)

        -- In minimized mode, hide ignored vehicle types from the search results.
        -- In expanded mode they remain visible so they can be restored with the undo button.
        local isIgnored = ignoredVehicles[name] == true
        if isInRange(distance) and not isIgnored then
            if not seenVehicleModels[model] then
                showDetectionNotification("CAR", name)
            end
            seenVehicleModels[model] = true
            table.insert(results, {
                model = model,
                name = name,
                distance = distance or math.huge
            })
        end
    end

    table.sort(results, function(a, b)
        local af, bf = favoriteVehicles[a.name] == true, favoriteVehicles[b.name] == true
        if af ~= bf then return af end
        return a.distance < b.distance
    end)

    local currentVehicleModels = {}
    for _, entry in ipairs(results) do currentVehicleModels[entry.model] = true end
    for model in pairs(seenVehicleModels) do
        if not model or not model.Parent or not currentVehicleModels[model] then
            seenVehicleModels[model] = nil
        end
    end
    vehicles = results

    liveStatus.Text = "● LIVE TRACKING"
    liveStatus.TextColor3 = Theme.Accent

    renderVehicles()
end

-- Boss scanner: detects any child whose name begins with "boss_".
local function getBossFolder()
    local hushLocal = workspace:FindFirstChild("HushLocal")
    local zombieFolder = hushLocal and hushLocal:FindFirstChild("Zombies")
    return zombieFolder
end

local function clearBossRows()
    for _, parent in ipairs({bossList, compactCombinedList, compactBossColumn}) do
        for _, child in ipairs(parent:GetChildren()) do
            if child.Name == "BossRow" or child.Name == "BossEmptyLabel" then child:Destroy() end
        end
    end
    bossRows = {}
end

local function scanBosses()
    if not running then return end
    local folder = getBossFolder()
    local found = {}
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if string.sub(string.lower(model.Name), 1, 5) == "boss_" then
                if not seenBossModels[model] then
                    showDetectionNotification("BOSS", model.Name)
                end
                seenBossModels[model] = true
                local distance, arrow, direction = getTrackingInfo(model)
                table.insert(found, {model = model, name = model.Name, distance = distance or math.huge, arrow = arrow, direction = direction})
            end
        end
    end
    local currentBossModels = {}
    for _, entry in ipairs(found) do currentBossModels[entry.model] = true end
    for model in pairs(seenBossModels) do
        if not model or not model.Parent or not currentBossModels[model] then
            seenBossModels[model] = nil
        end
    end
    table.sort(found, function(a, b) return a.distance < b.distance end)
    bosses = found
    compactCount.Text = string.format("%d cars  •  %d bosses", #vehicles, #bosses)
    clearBossRows()
    for index, data in ipairs(bosses) do
        local row = button(minimized and compactBossColumn or bossList, "", data.model == selectedBoss and Theme.Selected or Theme.Surface)
        row.Name = "BossRow"
        row.Size = UDim2.new(1, -3, 0, minimized and 28 or 38)
        row.LayoutOrder = index
        row.Text = ""
        local nameLabel = text(row, data.name, 11, Theme.Text, true)
        nameLabel.Position = UDim2.new(0, 9, 0, 3)
        nameLabel.Size = UDim2.new(0.55, 0, 1, -6)
        local infoLabel = text(row, string.format("%s %.0f", data.arrow or "?", data.distance), 10, Theme.Accent, true)
        infoLabel.Position = UDim2.new(0.56, 0, 0, 3)
        infoLabel.Size = UDim2.new(0.41, -8, 1, -6)
        infoLabel.TextXAlignment = Enum.TextXAlignment.Right
        bossRows[data.model] = row
        row.MouseButton1Click:Connect(function()
            selectedBoss = selectedBoss == data.model and nil or data.model
            scanBosses()
        end)
    end
    if #bosses == 0 then
        local empty = text(minimized and compactBossColumn or bossList, folder and "No boss detected" or "Waiting for HushLocal.Zombies", 10, Theme.Muted)
        empty.Name = "BossEmptyLabel"
        empty.Size = UDim2.new(1, 0, 0, 34)
        empty.TextXAlignment = Enum.TextXAlignment.Center
    end
    bossCount.Text = tostring(#bosses) .. " bosses detected"
    if selectedBoss and not selectedBoss.Parent then selectedBoss = nil end
end

local function updateSelectedVehicleLine()
    if not selectedVehicle or not selectedVehicle.Parent then
        targetTracer.Visible = false
        targetTracerDot.Visible = false
        vehicleWaypoint.Visible = false
        return
    end

    local worldPosition = getVehiclePosition(selectedVehicle)
    local camera = workspace.CurrentCamera
    local characterRoot = getRoot()

    if not worldPosition or not camera or not characterRoot then
        targetTracer.Visible = false
        targetTracerDot.Visible = false
        vehicleWaypoint.Visible = false
        return
    end

    -- Project the actual player character and selected vehicle into screen space.
    local playerScreen, playerOnScreen =
        camera:WorldToViewportPoint(characterRoot.Position)
    local vehicleScreen, vehicleOnScreen =
        camera:WorldToViewportPoint(worldPosition)

    local viewport = camera.ViewportSize
    local distance = getTrackingInfo(selectedVehicle)
    local vehicleType = selectedVehicle:GetAttribute("VehType")
    local vehicleName = type(vehicleType) == "string"
        and vehicleType ~= "" and vehicleType
        or selectedVehicle.Name

    waypointText.Text = string.format(
        "%s  •  %.0f studs",
        vehicleName,
        distance or 0
    )

    -- Keep a waypoint visible at the vehicle's screen position. If the car
    -- is outside the view, clamp the marker to the nearest screen edge.
    local markerX = vehicleScreen.X
    local markerY = vehicleScreen.Y
    if vehicleScreen.Z <= 0 then
        markerX = viewport.X - markerX
        markerY = viewport.Y - markerY
    end

    local marginX = vehicleWaypoint.AbsoluteSize.X * 0.5 + 8
    local marginY = vehicleWaypoint.AbsoluteSize.Y + 8
    markerX = math.clamp(markerX, marginX, viewport.X - marginX)
    markerY = math.clamp(markerY, marginY, viewport.Y - 8)

    vehicleWaypoint.Position = UDim2.fromOffset(markerX, markerY)
    vehicleWaypoint.Visible = true

    if not playerOnScreen or not vehicleOnScreen
        or playerScreen.Z <= 0 or vehicleScreen.Z <= 0
        or playerScreen.X < 0 or playerScreen.X > viewport.X
        or playerScreen.Y < 0 or playerScreen.Y > viewport.Y
        or vehicleScreen.X < 0 or vehicleScreen.X > viewport.X
        or vehicleScreen.Y < 0 or vehicleScreen.Y > viewport.Y then
        targetTracer.Visible = false
        targetTracerDot.Visible = false
        return
    end

    -- Draw directly from the player's on-screen position to the car.
    local startX = playerScreen.X
    local startY = playerScreen.Y
    local endX = vehicleScreen.X
    local endY = vehicleScreen.Y
    local dx = endX - startX
    local dy = endY - startY
    local length = math.sqrt(dx * dx + dy * dy)

    -- Roblox rotates GuiObjects around their center. Place the line's
    -- center at the midpoint so both endpoints land on the projected points.
    local midX = (startX + endX) * 0.5
    local midY = (startY + endY) * 0.5

    targetTracer.Position = UDim2.fromOffset(midX, midY)
    targetTracer.Size = UDim2.fromOffset(length, 3)
    targetTracer.Rotation = math.deg(math.atan2(dy, dx))
    targetTracer.Visible = true

    targetTracerDot.Position = UDim2.fromOffset(endX, endY)
    targetTracerDot.Visible = true
end

local function updateTracking()
    if not running then return end

    for model, row in pairs(vehicleRows) do
        if model and model.Parent and row.button.Parent then
            local distance, arrow, direction =
                getTrackingInfo(model)

            row.infoLabel.Text =
                arrow .. " " .. formatDistance(distance)

            row.button.BackgroundColor3 =
                model == selectedVehicle
                and Theme.Selected
                or Theme.Surface
        end
    end

    if selectedVehicle and selectedVehicle.Parent then
        local distance, arrow, direction =
            getTrackingInfo(selectedVehicle)

        local vehType =
            selectedVehicle:GetAttribute("VehType")

        targetName.Text =
            type(vehType) == "string" and vehType ~= ""
            and vehType
            or selectedVehicle.Name

        targetDistance.Text =
            arrow .. " " .. direction ..
            "  |  " .. formatDistance(distance)
    else
        selectedVehicle = nil

        targetName.Text = "No vehicle selected"
        targetDistance.Text = "Tap a vehicle to track"
    end

    updateSelectedVehicleLine()
end

--========================================================
-- MINIMIZE / CLOSE
--========================================================

-- Compact mode: show cars and bosses together in one list.
local function setCompactVehicleList(enabled)
    minimized = enabled
    if enabled then
        sidebar.Visible = false
        content.Position = UDim2.new(0, 0, 0, 0)
        content.Size = UDim2.new(1, 0, 1, 0)
        for pageName, page in pairs(pages) do page.Visible = pageName == "Tracker" end
        trackerTitle.Visible = false
        trackerSubtitle.Visible = false
        liveStatus.Visible = false
        targetPanel.Visible = false
        listTitle.Visible = false
        vehicleESPToggle.Visible = false
        compactTabs.Visible = false
        vehicleCount.Visible = false
        bossCount.Visible = false
        compactCount.Visible = true
        compactCombinedList.Visible = false
        compactBossTitle.Visible = true
        compactCarTitle.Visible = true
        compactBossColumn.Visible = true
        compactCarColumn.Visible = true
        vehicleList.Visible = false
        bossList.Visible = false
        sidebar.Visible = false
        body.Position = UDim2.new(0, 0, 0, 28)
        body.Size = UDim2.new(1, 0, 1, -28)
        content.Position = UDim2.new(0, 0, 0, 0)
        content.Size = UDim2.new(1, 0, 1, 0)
        -- Compact HUD-style panel: slightly inset from the upper-left.
        main.AnchorPoint = Vector2.new(0, 0)
        main.Position = UDim2.new(0, 330, 0, 8)
        main.Size = UDim2.new(0, 500, 0, 190)
        header.Size = UDim2.new(1, 0, 0, 28)
        logo.Visible = false
        version.Visible = false
        minimize.Position = UDim2.new(1, -54, 0, 3)
        minimize.Size = UDim2.new(0, 22, 0, 22)
        close.Position = UDim2.new(1, -28, 0, 3)
        close.Size = UDim2.new(0, 22, 0, 22)
        compactCount.Position = UDim2.new(0, 10, 0, 1)
        compactCount.Size = UDim2.new(1, -20, 0, 15)
        compactBossTitle.Position = UDim2.new(0, 10, 0, 20)
        compactBossTitle.Size = UDim2.new(0.5, -15, 0, 14)
        compactCarTitle.Position = UDim2.new(0.5, 5, 0, 20)
        compactCarTitle.Size = UDim2.new(0.5, -15, 0, 14)
        compactBossColumn.Position = UDim2.new(0, 8, 0, 37)
        compactBossColumn.Size = UDim2.new(0.5, -12, 1, -42)
        compactCarColumn.Position = UDim2.new(0.5, 4, 0, 37)
        compactCarColumn.Size = UDim2.new(0.5, -12, 1, -42)
        minimize.Text = "+"
        scanVehicles()
        scanBosses()
    else
        sidebar.Visible = true
        body.Position = UDim2.new(0, 0, 0, 46)
        body.Size = UDim2.new(1, 0, 1, -46)
        content.Position = UDim2.new(0, 155, 0, 0)
        content.Size = UDim2.new(1, -155, 1, 0)
        main.AnchorPoint = Vector2.new(0, 0)
        main.Position = UDim2.new(0.5, -290, 0.5, -195)
        main.Size = UDim2.new(0, 580, 0, 390)
        header.Size = UDim2.new(1, 0, 0, 46)
        logo.Visible = true
        version.Visible = true
        minimize.Position = UDim2.new(1, -76, 0, 9)
        minimize.Size = UDim2.new(0, 29, 0, 28)
        close.Position = UDim2.new(1, -40, 0, 9)
        close.Size = UDim2.new(0, 29, 0, 28)
        compactCount.Position = UDim2.new(0, 12, 0, 36)
        compactCount.Size = UDim2.new(1, -24, 0, 20)
        compactCombinedList.Position = UDim2.new(0, 10, 0, 60)
        compactCombinedList.Size = UDim2.new(1, -20, 1, -70)
        compactBossColumn.Position = UDim2.new(0, 8, 0, 37)
        compactBossColumn.Size = UDim2.new(0.5, -12, 1, -42)
        compactCarColumn.Position = UDim2.new(0.5, 4, 0, 37)
        compactCarColumn.Size = UDim2.new(0.5, -12, 1, -42)
        sidebar.Visible = true
        content.Position = UDim2.new(0, 155, 0, 0)
        content.Size = UDim2.new(1, -155, 1, 0)
        trackerTitle.Visible = true
        trackerSubtitle.Visible = true
        liveStatus.Visible = true
        targetPanel.Visible = true
        listTitle.Visible = true
        vehicleESPToggle.Visible = true
        compactTabs.Visible = false
        compactCount.Visible = false
        compactCombinedList.Visible = false
        compactBossTitle.Visible = false
        compactCarTitle.Visible = false
        compactBossColumn.Visible = false
        compactCarColumn.Visible = false
        vehicleList.Visible = true
        bossList.Visible = false
        bossCount.Visible = false
        vehicleCount.Visible = true
        vehicleCount.Position = UDim2.new(1, -145, 0, 60)
        vehicleCount.Size = UDim2.new(0, 125, 0, 22)
        vehicleCount.TextXAlignment = Enum.TextXAlignment.Right
        vehicleList.Position = UDim2.new(0, 16, 0, 196)
        vehicleList.Size = UDim2.new(1, -32, 1, -204)
        showPage("Tracker")
        minimize.Text = "—"
        scanVehicles()
        scanBosses()
    end
end

minimize.MouseButton1Click:Connect(function()
    setCompactVehicleList(not minimized)
end)

-- Right Shift toggles compact/minimized mode.
UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or not running then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        setCompactVehicleList(not minimized)
    end
end)

-- CLEANUP
--========================================================

local function cleanup()
    if not running then return end

    running = false
    zombieESPEnabled = false
    vehicleESPEnabled = false
    militaryMapEnabled = false

    clearMilitaryMapHighlight()
    clearZombieESP()
    clearVehicleESP()
    if cordonMapDraw and originalCordonFogRects then
        fullMapRevealEnabled = false
        pcall(function()
            cordonMapDraw.fogRects = originalCordonFogRects
        end)
        pcall(repaintCordonFog)
    end
    targetTracer.Visible = false
    targetTracerDot.Visible = false
    vehicleWaypoint.Visible = false
    targetTracer:Destroy()
    targetTracerDot:Destroy()
    vehicleWaypoint:Destroy()

    for _, conn in ipairs(connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end

    gui:Destroy()
end

_G.VezaStop = cleanup

-- Persist the current state before the UI is closed.
local originalCleanup = cleanup
cleanup = function()
    if RememberSettings then
        saveConfig()
    end
    saveVehicleLists()
    restoreCameraZoom()
    originalCleanup()
end
_G.VezaStop = cleanup
close.MouseButton1Click:Connect(cleanup)

--========================================================
-- PAGE 7: CORDON FULL MAP REVEAL (LOCAL VISUAL ONLY)
--========================================================

local mapRevealPage = registerPage("MapReveal", "Map Reveal", 7)
local mapRevealTitle = text(mapRevealPage, "Cordon Map Reveal", 16, Theme.Text, true)
mapRevealTitle.Position = UDim2.new(0, 16, 0, 12)
mapRevealTitle.Size = UDim2.new(1, -32, 0, 25)

local mapRevealSubtitle = text(
    mapRevealPage,
    "Remove the minimap fog layer locally",
    10, Theme.Muted
)
mapRevealSubtitle.Position = UDim2.new(0, 16, 0, 37)
mapRevealSubtitle.Size = UDim2.new(1, -32, 0, 20)

local mapRevealPanel = create("Frame", {
    Size = UDim2.new(1, -32, 0, 94),
    Position = UDim2.new(0, 16, 0, 72),
    BackgroundColor3 = Theme.Surface,
    BackgroundTransparency = 0.16,
    BorderSizePixel = 0
}, mapRevealPage)
round(mapRevealPanel, 7)

local mapRevealOption = text(
    mapRevealPanel, "FULL MAP REVEAL",
    12, Theme.Text, true
)
mapRevealOption.Position = UDim2.new(0, 12, 0, 10)
mapRevealOption.Size = UDim2.new(0.65, 0, 0, 22)

local mapRevealDescription = text(
    mapRevealPanel,
    "Shows all map areas available in the client extract",
    9, Theme.Muted
)
mapRevealDescription.Position = UDim2.new(0, 12, 0, 35)
mapRevealDescription.Size = UDim2.new(0.68, 0, 0, 30)
mapRevealDescription.TextWrapped = true

local mapRevealToggle = button(mapRevealPanel, "ON", Theme.Accent)
mapRevealToggle.Position = UDim2.new(1, -76, 0, 27)
mapRevealToggle.Size = UDim2.new(0, 62, 0, 32)

local mapRevealStatus = text(
    mapRevealPage, "STATUS: WAITING FOR CORDON MAP MODULE",
    10, Theme.Muted, true
)
mapRevealStatus.Position = UDim2.new(0, 16, 0, 182)
mapRevealStatus.Size = UDim2.new(1, -32, 0, 24)

local mapRevealInfo = text(
    mapRevealPage,
    "Client-side visual only. Does not modify server exploration progress or reveal data that is not included in the public map extract.",
    10, Theme.Muted
)
mapRevealInfo.Position = UDim2.new(0, 16, 0, 211)
mapRevealInfo.Size = UDim2.new(1, -32, 0, 58)
mapRevealInfo.TextWrapped = true

-- Enabled by default each time VEZA starts.
local fullMapRevealEnabled = true
local cordonMapDraw = nil
local originalCordonFogRects = nil

local function findCordonMapDraw()
    if cordonMapDraw
        and type(cordonMapDraw.fogRects) == "function"
        and type(cordonMapDraw.fogState) == "function"
        and type(cordonMapDraw.see) == "function" then
        return cordonMapDraw
    end

    if type(getgc) ~= "function" then
        return nil, "GETGC UNAVAILABLE"
    end

    local ok, objects = pcall(getgc, true)
    if not ok or type(objects) ~= "table" then
        return nil, "CANNOT READ CLIENT TABLES"
    end

    for _, object in ipairs(objects) do
        if type(object) == "table"
            and object.FOG_MAX == 320
            and object.SIGHT == 160
            and type(object.extract) == "function"
            and type(object.fogRects) == "function"
            and type(object.fogState) == "function"
            and type(object.see) == "function" then
            cordonMapDraw = object
            originalCordonFogRects = object._VEZA_OriginalFogRects or object.fogRects
            pcall(function()
                object._VEZA_OriginalFogRects = originalCordonFogRects
            end)
            return object
        end
    end

    return nil, "WAITING FOR CORDON MAP DRAW"
end

local function repaintCordonFog()
    local module = cordonMapDraw
    if not module then return false end

    local ok, result = pcall(function()
        local extract = module.extract()
        if type(extract) ~= "table" then return false end
        local mask = module.fogState()
        if type(mask) ~= "table" then return false end

        local character = Player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root or not root:IsA("BasePart") then return false end

        local chunk = (type(extract.chunk) == "number" and extract.chunk > 0)
            and extract.chunk or 128
        local half = extract.size * chunk / 2
        local col = math.clamp(math.floor((root.Position.X + half) / chunk), 0, extract.size - 1)
        local row = math.clamp(math.floor((root.Position.Z + half) / chunk), 0, extract.size - 1)
        local index = row * extract.size + col

        -- Clear and immediately re-see the player's current cell. This forces
        -- the module's own paintFog() routine to redraw using the selected mode.
        if mask[index] then
            mask[index] = nil
        end
        module.see(root.Position.X, root.Position.Z)
        return true
    end)

    return ok and result == true
end

local function applyCordonFogMode()
    local module, reason = findCordonMapDraw()
    if not module then
        mapRevealStatus.Text = "STATUS: " .. tostring(reason)
        mapRevealStatus.TextColor3 = Theme.Muted
        return false
    end

    local original = originalCordonFogRects or module._VEZA_OriginalFogRects
        or module.fogRects
    originalCordonFogRects = original
    pcall(function()
        module._VEZA_OriginalFogRects = original
    end)

    local patchOK, patchError = pcall(function()
        if fullMapRevealEnabled then
            module.fogRects = function()
                return {}, 0
            end
        else
            module.fogRects = original
        end
    end)
    if not patchOK then
        mapRevealStatus.Text = "STATUS: FOG HOOK BLOCKED"
        mapRevealStatus.TextColor3 = Theme.Red
        warn("[VEZA] Cordon fog hook failed: " .. tostring(patchError))
        return false
    end

    repaintCordonFog()
    mapRevealStatus.Text = fullMapRevealEnabled
        and "STATUS: FULL MAP REVEAL ACTIVE"
        or "STATUS: NORMAL FOG RESTORED"
    mapRevealStatus.TextColor3 = fullMapRevealEnabled and Theme.Accent or Theme.Muted
    return true
end

local function updateMapRevealToggle()
    mapRevealToggle.Text = fullMapRevealEnabled and "ON" or "OFF"
    mapRevealToggle.BackgroundColor3 = fullMapRevealEnabled and Theme.Accent or Theme.Border
end

mapRevealToggle.MouseButton1Click:Connect(function()
    fullMapRevealEnabled = not fullMapRevealEnabled
    updateMapRevealToggle()
    if not applyCordonFogMode() then
        mapRevealStatus.Text = fullMapRevealEnabled
            and "STATUS: ENABLED — WAITING FOR MAP"
            or "STATUS: DISABLED — WAITING FOR MAP"
    end
end)

--========================================================
-- BACKGROUND LOOPS
--========================================================

-- Force Day + No Snow: retry until the game's Atmosphere controller exists.
task.spawn(function()
    while running and gui.Parent do
        if forceDayNoSnowEnabled then
            applyDayNoSnow()
        end
        task.wait(2)
    end
end)

-- Cordon fog hook: retry until the map module is loaded, then keep the
-- selected local fog mode applied if the game rebuilds its map module.
updateMapRevealToggle()
task.spawn(function()
    local lastModule = nil
    while running and gui.Parent do
        local module = findCordonMapDraw()
        if module then
            if module ~= lastModule then
                lastModule = module
                applyCordonFogMode()
            elseif fullMapRevealEnabled and module.fogRects ~= nil
                and module.fogRects == originalCordonFogRects then
                -- Re-apply if another local script restored the original function.
                applyCordonFogMode()
            end
        end
        task.wait(1)
    end
end)

-- Vehicle list scan
task.spawn(function()
    while running and gui.Parent do
        scanVehicles()
        task.wait(Settings.ScanInterval)
    end
end)

-- Boss scanner refresh
task.spawn(function()
    while running and gui.Parent do
        scanBosses()
        task.wait(Settings.ScanInterval)
    end
end)

-- Vehicle distance and direction updates
task.spawn(function()
    while running and gui.Parent do
        updateTracking()
        task.wait(Settings.UpdateInterval)
    end
end)

-- Vehicle ESP scan
task.spawn(function()
    while running and gui.Parent do
        if vehicleESPEnabled then
            scanVehicleESP()
        end
        task.wait(Settings.ScanInterval)
    end
end)

-- Military map highlight refresh
task.spawn(function()
    while running and gui.Parent do
        if militaryMapEnabled then
            scanMilitaryMap()
        end
        task.wait(1)
    end
end)

-- Zombie ESP scan
task.spawn(function()
    while running and gui.Parent do
        if zombieESPEnabled then
            scanZombies()
        end

        task.wait(Settings.ZombieScanInterval)
    end
end)

--========================================================
-- INITIALIZE
--========================================================

updateSlider()
updateUnlimited()
updateRememberUI()
updateZoomUI()
updateZombieToggle()
updateVehicleToggle()
updateMilitaryToggle()
updateEnvironmentToggle()

showPage("Tracker")

-- Start in the existing compact/minimized HUD mode on first execution.
-- The header "+" button (and Right Shift) can restore the full GUI.
setCompactVehicleList(true)

if RememberSettings then
    saveConfig()
end

if ZoomEnabled then
    task.spawn(function()
        while running and gui.Parent do
            if applyCameraZoom() then
                preferenceStatus.Text = "Status: camera zoom patched"
                break
            end
            task.wait(1)
        end
    end)
end

scanVehicles()
updateTracking()

print("================================")
print("       VEZA GUI v3.4")
print("================================")
print("Vehicle Tracker: READY")
print("Distance Settings: READY")
print("Zombie ESP: READY")
print("Vehicle ESP: READY")
print("Player-to-Vehicle Tracer: READY")
print("Vehicle Waypoint: READY")
print("Military Map Highlight: READY")
print("Preferences + Camera Zoom: READY")
print("Force Day + No Snow: AUTO ON")
print("Cordon Full Map Reveal: AUTO ON")
print("Boss Scanner: READY")
print("Vehicle Favorites / Ignore: READY")
print("================================")
