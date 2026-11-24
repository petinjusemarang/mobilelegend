
-- HUSH AUTO SCRIPT LOADER v1.0

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LP = Players.LocalPlayer

local URLS = {
    ["IN-GAME"] = "https://raw.githubusercontent.com/petinjusemarang/mobilelegend/refs/heads/main/hush.lua",
    ["LOBBY"] = "https://raw.githubusercontent.com/petinjusemarang/mobilelegend/refs/heads/main/lobbyhush.lua"
}

local lastState = nil
local loading = false

local function detectState()
    local pg = LP:FindFirstChild("PlayerGui")

    local lobbyScore = 0
    local gameScore = 0

    local function check(object, points, isLobby)
        if object then
            if isLobby then
                lobbyScore += points
            else
                gameScore += points
            end
        end
    end

    -- LOBBY
    check(Workspace:FindFirstChild("HushLobby"), 3, true)
    check(pg and pg:FindFirstChild("HushLobbyCta"), 2, true)
    check(pg and pg:FindFirstChild("HushMenu"), 2, true)

    -- IN-GAME
    check(Workspace:FindFirstChild("HushArena"), 3, false)
    check(pg and pg:FindFirstChild("HushHUD"), 3, false)
    check(pg and pg:FindFirstChild("HushReticle"), 2, false)
    check(pg and pg:FindFirstChild("HushHUDFx"), 1, false)
    check(pg and pg:FindFirstChild("HushEventCard"), 1, false)

    if lobbyScore >= 3 and lobbyScore - gameScore >= 2 then
        return "LOBBY"
    elseif gameScore >= 3 and gameScore - lobbyScore >= 2 then
        return "IN-GAME"
    end

    return "UNKNOWN"
end

local function executeScript(state)
    local url = URLS[state]
    if not url then return end

    loading = true

    print("[HUSH LOADER] Loading: " .. state)

    local success, result = pcall(function()
        local source = game:HttpGet(url)
        local func = loadstring(source)

        assert(func, "Failed to compile script")

        return func()
    end)

    if success then
        print("[HUSH LOADER] Successfully executed: " .. state)
    else
        warn("[HUSH LOADER] ERROR: " .. tostring(result))
    end

    loading = false
end

print("[HUSH LOADER] Started")

task.spawn(function()
    while true do
        local state = detectState()

        if state ~= "UNKNOWN"
            and state ~= lastState
            and not loading then

            print("[HUSH LOADER] State changed: " .. state)

            lastState = state
            executeScript(state)
        end

        task.wait(1)
    end
end)
