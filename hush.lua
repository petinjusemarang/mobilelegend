--[[
========================================================
             OVERTURE MAP HELPER v1.1
========================================================
Based on the exact Environment Override and Hush Camera
Zoom functions from VEZA GUI v3.4.

- Force Day + No Snow (AUTO ON)
- Hush Camera Zoom (AUTO ON)
- Simple draggable GUI
- No scanners / ESP modules
========================================================
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

--========================================================
-- CLEANUP PREVIOUS VERSION
--========================================================

if _G.OvertureHelperStop then
    pcall(_G.OvertureHelperStop)
end

local previousGui = PlayerGui:FindFirstChild("OvertureMapHelper")
if previousGui then
    previousGui:Destroy()
end

--========================================================
-- SETTINGS (same defaults as VEZA)
--========================================================

local ZoomEnabled = true
local ZoomDistance = 300
local SavedZoomOriginal = nil
local CameraZoomController = nil

local forceDayNoSnowEnabled = true
local atmosphereController = nil

local running = true
local connections = {}

--========================================================
-- EXACT HUSH CAMERA ZOOM FUNCTIONS FROM VEZA v3.4
--========================================================

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

--========================================================
-- EXACT ENVIRONMENT FUNCTIONS FROM VEZA v3.4
--========================================================

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

--========================================================
-- GUI THEME / HELPERS
--========================================================

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

--========================================================
-- GUI
--========================================================

local gui = create("ScreenGui", {
    Name = "OvertureMapHelper",
    ResetOnSpawn = false,
    DisplayOrder = 999,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling
}, PlayerGui)

local main = create("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(270, 205),
    Position = UDim2.new(0, 22, 0.35, 0),
    BackgroundColor3 = Theme.Background,
    BackgroundTransparency = 0.05,
    BorderSizePixel = 0
}, gui)
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

local function updateToggle(toggle, enabled, onText, offText)
    toggle.Text = enabled and onText or offText
    toggle.BackgroundColor3 = enabled and Theme.Accent or Theme.Border
end

--========================================================
-- DRAG GUI (MOUSE + TOUCH)
--========================================================

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

--========================================================
-- TOGGLES
--========================================================

local function setEnvironmentStatus(message, active)
    environmentStatus.Text = "STATUS: " .. message
    environmentStatus.TextColor3 = active and Theme.Accent or Theme.Muted
end

local function setZoomStatus(message, active)
    zoomStatus.Text = "STATUS: " .. message
    zoomStatus.TextColor3 = active and Theme.Accent or Theme.Muted
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

--========================================================
-- CLEANUP
--========================================================

local function cleanup()
    if not running then return end
    running = false

    if forceDayNoSnowEnabled then
        restoreEnvironment()
    end

    restoreCameraZoom()

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

--========================================================
-- AUTO ON: RETRY UNTIL GAME MODULES ARE READY
--========================================================

updateToggle(environmentToggle, forceDayNoSnowEnabled, "ON", "OFF")
updateToggle(zoomToggle, ZoomEnabled, "ON", "OFF")

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
print("[OVERTURE HELPER] Loaded")
