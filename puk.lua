-- ============================================================
-- FULL AUTO RACING SCRIPT (LOOP SYSTEM + AI)
-- ============================================================

--// SAMLONG FPS BOOST - ULTRA LIGHT (NO LOOP)

local workspace = game:GetService("Workspace")
local lighting = game:GetService("Lighting")

local targets = {
    "MANDALIKA",
    "PROPS_GUNUNG",
    "PROPS_BANGUNAN",
    "SETTING_LAMPU",
    "SETTING_POHON_KOTA",
    "SETTING_POHON_FLYOVER",
    "SETTING_POHON_TOL",
    "LAMPU_PERTIGAAN",
    "LAMPU_PEREMPATAN"
}

for _, name in ipairs(targets) do
    local obj = workspace:FindFirstChild(name)
    if obj then
        obj:Destroy()
    end
end

local terrain = workspace:FindFirstChildOfClass("Terrain")
if terrain and terrain:FindFirstChild("Clouds") then
    terrain.Clouds:Destroy()
end

local descendants = game:GetDescendants()
for i, v in ipairs(descendants) do
    pcall(function()
        if v:IsA("Decal") or v:IsA("Texture") then
            v.Transparency = 1 -- Jangan Destroy, Adonis bisa detect
        elseif v:IsA("SurfaceAppearance") then
            pcall(function() v.Parent = nil end)
        elseif v:IsA("ParticleEmitter")
            or v:IsA("Trail")
            or v:IsA("Beam")
            or v:IsA("Smoke")
            or v:IsA("Fire")
            or v:IsA("Sparkles") then
            v.Enabled = false
        elseif v:IsA("BasePart") then
            v.Material = Enum.Material.SmoothPlastic
            v.CastShadow = false
            v.Reflectance = 0
        end
    end)
    -- Yield setiap 500 objek supaya game ga nge-freeze dan connection ga RTO
    if i % 500 == 0 then
        task.wait()
    end
end

lighting.GlobalShadows = false
lighting.Brightness = 1
lighting.FogEnd = 9e9

for _, v in ipairs(lighting:GetDescendants()) do
    if v:IsA("PostEffect") then
        v.Enabled = false
    end
end

settings().Rendering.QualityLevel = Enum.QualityLevel.Level01

print("✅ FPS BOOST APPLIED (ULTRA LIGHT MODE)")

local RunService = game:GetService("RunService")
local player     = game:GetService("Players").LocalPlayer

-- ===== ANTI-AFK (EXECUTOR NATIVE - 100% STEALTH) =====
task.spawn(function()
    player.Idled:Connect(function()
        -- Kalau executor mensupport fungsi input level OS
        if keypress and keyrelease then
            pcall(function()
                keypress(0x00)
                keyrelease(0x00)
            end)
        elseif mousemoverel then
            pcall(function()
                mousemoverel(1, 1)
                task.wait()
                mousemoverel(-1, -1)
            end)
        else
            -- Fallback bypass (aman karena tidak call GetService)
            pcall(function()
                if getconnections then
                    for _, conn in ipairs(getconnections(player.Idled)) do
                        conn:Disable()
                    end
                end
            end)
        end
        print("✅ Anti-AFK Ping Dikirim.")
    end)
end)

-- ===== FUNCTION STATUS GUI =====
local function createStatusGui()
    local screenGui = player.PlayerGui:FindFirstChild("SamlongStatus")
    if screenGui then screenGui:Destroy() end

    screenGui = Instance.new("ScreenGui", player.PlayerGui)
    screenGui.Name = "SamlongStatus"

    local label = Instance.new("TextLabel", screenGui)
    label.Size = UDim2.new(0, 300, 0, 50)
    label.Position = UDim2.new(0.5, -150, 0.8, 0)
    label.BackgroundTransparency = 0.3
    label.BackgroundColor3 = Color3.fromRGB(0,0,0)
    label.TextColor3 = Color3.fromRGB(255,255,255)
    label.TextScaled = true

    return label
end

local statusLabel = createStatusGui()
local function setStatus(text)
    statusLabel.Text = text
    print("[STATUS]", text)
end

-- ===== MONEY / RP GUI =====
local function createMoneyGui()
    local screenGui = player.PlayerGui:FindFirstChild("SamlongMoney")
    if screenGui then screenGui:Destroy() end

    screenGui = Instance.new("ScreenGui", player.PlayerGui)
    screenGui.Name = "SamlongMoney"
    screenGui.ResetOnSpawn = false

    local frame = Instance.new("Frame", screenGui)
    frame.Size = UDim2.new(0, 220, 0, 40)
    frame.Position = UDim2.new(0, 10, 0, 10)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    frame.BackgroundTransparency = 0.3
    frame.BorderSizePixel = 0
    pcall(function()
        local corner = Instance.new("UICorner", frame)
        corner.CornerRadius = UDim.new(0, 8)
    end)

    local icon = Instance.new("TextLabel", frame)
    icon.Size = UDim2.new(0, 35, 1, 0)
    icon.Position = UDim2.new(0, 5, 0, 0)
    icon.BackgroundTransparency = 1
    icon.Text = "💰"
    icon.TextSize = 20
    icon.Font = Enum.Font.GothamBold

    local rpLabel = Instance.new("TextLabel", frame)
    rpLabel.Size = UDim2.new(1, -45, 1, 0)
    rpLabel.Position = UDim2.new(0, 40, 0, 0)
    rpLabel.BackgroundTransparency = 1
    rpLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    rpLabel.TextSize = 18
    rpLabel.Font = Enum.Font.GothamBold
    rpLabel.TextXAlignment = Enum.TextXAlignment.Left
    rpLabel.Text = "Rp 0"

    return rpLabel
end

local moneyLabel = createMoneyGui()

-- Auto-update RP setiap 2 detik
task.spawn(function()
    while true do
        pcall(function()
            local rpValue = player:FindFirstChild("PlayerData")
                and player.PlayerData:FindFirstChild("RPValue")
            if rpValue then
                -- Format angka pakai separator titik
                local val = tostring(rpValue.Value)
                local formatted = val:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
                moneyLabel.Text = "Rp " .. formatted
            end
        end)
        task.wait(2)
    end
end)

-- ============================================================
-- CHECKPOINTS  (control points — the spline curves through these)
-- ============================================================
local CHECKPOINTS = {
Vector3.new(-229.05, 7.77, -1615.53),
Vector3.new(1121.90, 7.78, -1616.90),
Vector3.new(1433.03, 7.78, -1542.41),
Vector3.new(1450.04, 7.77, -1406.42),
Vector3.new(1373.63, 7.78, -1109.98),
Vector3.new(1231.93, 7.77, -697.05),
Vector3.new(1046.10, 7.77, -730.86),
Vector3.new(981.43, 7.78, -727.86),
Vector3.new(853.89, 7.78, -535.31),
Vector3.new(906.34, 7.77, -415.98),
Vector3.new(1216.17, 7.77, 61.28),
Vector3.new(1189.69, 7.76, 204.35),
Vector3.new(1050.76, 7.77, 788.92),
Vector3.new(946.15, 7.76, 871.25),
Vector3.new(459.97, 7.77, 1209.84),
Vector3.new(397.92, 7.77, 1240.71),
Vector3.new(-1.37, 7.76, 1176.40),
Vector3.new(-146.47, 7.77, 1257.92),
Vector3.new(-424.42, 7.76, 1458.19),
Vector3.new(-621.51, 7.75, 1526.14),
Vector3.new(-1604.49, 7.74, 1793.94),
Vector3.new(-1707.82, 7.74, 1811.73),
Vector3.new(-1796.75, 7.75, 1708.61),
Vector3.new(-1544.94, 7.76, 892.61),
Vector3.new(-1503.64, 7.77, 799.17),
Vector3.new(-883.47, 7.77, 708.02),
Vector3.new(-783.56, 7.75, 604.78),
Vector3.new(-714.66, 7.75, 503.89),
Vector3.new(-574.10, 7.77, -371.67),
Vector3.new(-646.73, 7.77, -496.33),
Vector3.new(-1036.27, 7.78, -671.74),
Vector3.new(-1165.88, 7.75, -842.32),
Vector3.new(-1464.12, 7.75, -1701.22),
Vector3.new(-1426.51, 7.77, -2016.87),
Vector3.new(-1324.11, 7.77, -2151.50),
Vector3.new(-1160.40, 7.78, -2306.87),
Vector3.new(-1027.74, 7.78, -2249.82),
Vector3.new(-1014.72, 7.78, -2179.79),
Vector3.new(-1114.06, 7.77, -1930.37),
Vector3.new(-1199.69, 7.76, -1702.03),
Vector3.new(-1124.12, 7.75, -1615.50),
Vector3.new(-228.79, 7.77, -1612.75),
Vector3.new(-202.34, 7.77, -1613.01),
-- ===== RETURN PATH (finish → start) =====
Vector3.new(-212.66, 7.77, -1612.75),
Vector3.new(-227.16, 7.77, -1612.40),
Vector3.new(-246.45, 7.77, -1611.93),
Vector3.new(-266.05, 7.77, -1611.45),
Vector3.new(-285.44, 7.77, -1610.98),
Vector3.new(-304.94, 7.77, -1610.50),
Vector3.new(-324.33, 7.77, -1610.03),
Vector3.new(-343.73, 7.77, -1609.55),
}


-- ============================================================
-- CONFIG  (tune these to adjust feel)
-- ============================================================
local CFG = {
	maxSpeed       = 220,
	minSpeed       = 60,
	minPointDist   = 5.0,
	lookaheadSteps = 8,
	reachDist      = 20.0,
	steerRate      = math.rad(120),
	accelTau       = 0.8,
	decelTau       = 0.4,
	velTau         = 0.1,
	gyroP          = 2000,
	gyroD          = 250,
	velP           = 4000,
}

-- ============================================================
-- PATH GENERATION
-- ============================================================
local function simplifyPath(pts, minDistance)
	local out = {pts[1]}
	local lastPt = pts[1]
	for i = 2, #pts do
		if (pts[i] - lastPt).Magnitude >= minDistance then
			table.insert(out, pts[i])
			lastPt = pts[i]
		end
	end
	return out
end

-- Chaikin Spline (untuk smoothing)
local function chaikin(cps, passes)
	local pts = {}
	for i = 1, #cps do pts[i] = cps[i] end
	for _ = 1, passes do
		local out = {}
		local m   = #pts
		for i = 1, m do
			local a = pts[i]
			local b = pts[(i % m) + 1]
			table.insert(out, a * 0.75 + b * 0.25)
			table.insert(out, a * 0.25 + b * 0.75)
		end
		pts = out
	end
	return pts
end

-- 1. WAJIB: Simplify dulu (hapus titik rapat)
local simplifiedPts = simplifyPath(CHECKPOINTS, CFG.minPointDist)

-- 2. BARU PAKAI SPLINE (agar jalur smooth tapi tidak overfit)
local pathPoints = chaikin(simplifiedPts, 5)
local N = #pathPoints

-- Wrap-safe index helpers
local function wrapI(i) return ((i - 1) % N) + 1 end
local function stepI(i, s) return wrapI(i + s) end

-- ============================================================
-- AI CONTROLLER FUNCTIONS
-- ============================================================
local activeHeartbeat = nil
local activeBodyVel = nil
local activeBodyGyro = nil
local activeRoot = nil
local finishedRace = false




local function stopAI()
    if activeHeartbeat then
        activeHeartbeat:Disconnect()
        activeHeartbeat = nil
    end
    -- Hentikan semua velocity
    if activeRoot then
        pcall(function()
            activeRoot.AssemblyLinearVelocity  = Vector3.zero
            activeRoot.AssemblyAngularVelocity = Vector3.zero
        end)
    end
    if activeBodyVel then
        activeBodyVel.Velocity = Vector3.zero
        activeBodyVel:Destroy()
        activeBodyVel = nil
    end
    -- Hancurkan BodyGyro juga — harus di-cleanup bersih.
    if activeBodyGyro then
        activeBodyGyro:Destroy()
        activeBodyGyro = nil
    end
    finishedRace = true
end

local function runAI(root)
    -- Pastikan AI sebelumnya mati
    stopAI()
    finishedRace = false
    activeRoot = root

    -- PHYSICS
    activeBodyVel = Instance.new("BodyVelocity", root)
    activeBodyVel.MaxForce = Vector3.new(1e6, 0, 1e6)
    activeBodyVel.P        = CFG.velP

    activeBodyGyro = Instance.new("BodyGyro", root)
    activeBodyGyro.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
    activeBodyGyro.P         = CFG.gyroP
    activeBodyGyro.D         = CFG.gyroD

    -- RUNTIME STATE
    local speedMultiplier = math.random(85, 100) / 100
    local actualMaxSpeed = CFG.maxSpeed * speedMultiplier
    local actualMinSpeed = CFG.minSpeed * speedMultiplier

    local pathIdx = 10
    local speed = 0
    local curVel = Vector3.zero
    
    local isFinishing = false
    local finishTime = 0
    _G.triggerCoast = false

    task.wait(0.1) -- Dipercepat dari 1 detik jadi 0.1 detik agar start lebih instan

    local startTarget = pathPoints[pathIdx]
    local flatStartPos = Vector3.new(root.Position.X, 0, root.Position.Z)
    local flatTarget = Vector3.new(startTarget.X, 0, startTarget.Z)
    local initRaw = (flatTarget - flatStartPos).Unit

    root.CFrame = CFrame.lookAt(root.Position, root.Position + initRaw)
    local moveDir = initRaw
    activeBodyGyro.CFrame = root.CFrame

    -- MAIN LOOP AI
    activeHeartbeat = RunService.Heartbeat:Connect(function(dt)
        if finishedRace then return end
        dt = math.min(dt, 0.05)
        
        if _G.triggerCoast and not isFinishing then
            isFinishing = true
            finishTime = os.clock()
        end

        if isFinishing then
            local pos = root.Position
            local elapsed = os.clock() - finishTime
            local startPos = Vector3.new(-343.73, 0, -1609.55)

            local distToStart = (Vector3.new(pos.X, 0, pos.Z) - startPos).Magnitude
            
            -- Radius diperkecil ke 5 studs agar motor berhenti persis di titik start (maju maksimal)
            if distToStart < 5 or elapsed > 45 then
                speed = speed * 0.85
                if speed < 1 then
                    speed = 0
                    finishedRace = true
                    activeBodyVel.Velocity = Vector3.zero
                    return
                end
                curVel = curVel:Lerp(moveDir * speed, 1 - math.exp(-dt / CFG.velTau))
                activeBodyVel.Velocity = curVel
                return
            end

            -- Cari titik terdekat di depan untuk path pulang (hindari nyangkut)
            local bestIdx = pathIdx
            local minDistSq = math.huge
            for i = 0, 10 do
                local idx = pathIdx + i
                if idx <= N then
                    local pt = pathPoints[idx]
                    local distSq = (pt.X - pos.X)^2 + (pt.Z - pos.Z)^2
                    if distSq < minDistSq then
                        minDistSq = distSq
                        bestIdx = idx
                    end
                end
            end
            pathIdx = bestIdx

            if pathIdx <= N and minDistSq < 30 * 30 then
                pathIdx = pathIdx + 1
            end
            if pathIdx > N then pathIdx = N end

            -- Steer: selalu arahkan ke start position saat dekat (<150 studs)
            local rawDir
            if distToStart < 150 then
                rawDir = Vector3.new(startPos.X - pos.X, 0, startPos.Z - pos.Z)
            else
                local lookIdx = math.min(pathIdx + 5, N)
                local targetPt = pathPoints[lookIdx]
                rawDir = Vector3.new(targetPt.X - pos.X, 0, targetPt.Z - pos.Z)
            end
            if rawDir.Magnitude > 0.1 then
                moveDir = moveDir:Lerp(rawDir.Unit, math.min(dt * 6, 0.3)).Unit
            end

            -- Speed: tetap kencang sampai deket start biar ga diem
            local returnSpeed = 120
            if distToStart < 80 then
                returnSpeed = math.max(10, distToStart * 0.6)
            end
            -- Langsung lerp tanpa delay
            speed = speed + (returnSpeed - speed) * math.min(dt * 5, 0.25)

            curVel = curVel:Lerp(moveDir * speed, 1 - math.exp(-dt / CFG.velTau))
            activeBodyVel.Velocity = curVel
            activeBodyGyro.CFrame  = CFrame.lookAt(pos, pos + moveDir)
            return
        end
        
        local pos = root.Position
        local facing = root.CFrame.LookVector
        local flatFacing = Vector3.new(facing.X, 0, facing.Z).Unit

        -- Cari titik terdekat di depan (hindari nyangkut kalau motong jalan/miss point)
        local bestIdx = pathIdx
        local minDistSq = math.huge
        for i = 0, 15 do
            local idx = wrapI(pathIdx + i)
            local pt = pathPoints[idx]
            local distSq = (pt.X - pos.X)^2 + (pt.Z - pos.Z)^2
            if distSq < minDistSq then
                minDistSq = distSq
                bestIdx = idx
            end
        end
        pathIdx = bestIdx

        -- Kalau sudah sangat dekat, maju ke titik berikutnya
        if minDistSq < CFG.reachDist * CFG.reachDist then
            pathIdx = wrapI(pathIdx + 1)
        end

        local targetIdx = stepI(pathIdx, CFG.lookaheadSteps)
        local targetPt = pathPoints[targetIdx]
        local rawDir = Vector3.new(targetPt.X - pos.X, 0, targetPt.Z - pos.Z)
        local steerDir = rawDir.Magnitude > 0.1 and rawDir.Unit or moveDir
        
        local dotProduct = math.clamp(flatFacing:Dot(steerDir), -1, 1)
        local angle = math.deg(math.acos(dotProduct))

        local nextTargetPt = pathPoints[stepI(targetIdx, 10)]
        local dir2 = Vector3.new(nextTargetPt.X - targetPt.X, 0, nextTargetPt.Z - targetPt.Z).Unit
        local cornerDot = math.clamp(steerDir:Dot(dir2), -1, 1)
        local cornerAngle = math.deg(math.acos(cornerDot))
        
        local targetSpeed = actualMaxSpeed
        if cornerAngle < 15 then
            targetSpeed = actualMaxSpeed
        else
            local speedFactor = math.clamp((cornerDot + 1) / 2, 0, 1)
            speedFactor = math.pow(speedFactor, 0.4)
            targetSpeed = actualMinSpeed + (actualMaxSpeed - actualMinSpeed) * speedFactor
        end

        -- Hindari CFrame override karena bikin physics motor rusak (glitch/muter)
        -- Gunakan Lerp pada moveDir, lalu BodyGyro yang akan memutar motor secara natural
        if angle > 120 then
            targetSpeed = math.min(targetSpeed, actualMinSpeed * 0.5)
            moveDir = moveDir:Lerp(steerDir, 0.25).Unit
        elseif angle > 60 then
            targetSpeed = math.min(targetSpeed, actualMinSpeed)
            moveDir = moveDir:Lerp(steerDir, 0.15).Unit
        else
            moveDir = moveDir:Lerp(steerDir, 0.1).Unit
        end

        local flat = Vector3.new(moveDir.X, 0, moveDir.Z)
        if flat.Magnitude > 1e-4 then moveDir = flat.Unit end

        local tau = speed > targetSpeed and CFG.decelTau or CFG.accelTau
        speed = speed + (targetSpeed - speed) * (1 - math.exp(-dt / tau))

        curVel = curVel:Lerp(moveDir * speed, 1 - math.exp(-dt / CFG.velTau))
        
        activeBodyVel.Velocity = curVel
        activeBodyGyro.CFrame  = CFrame.lookAt(pos, pos + moveDir)
    end)
end

-- ============================================================
-- MAIN SYSTEM LOOP (AUTO RACE)
-- ============================================================

local roundCounter = 0
local MAX_ROUNDS = 7

task.spawn(function()
    while true do
        local character = player.Character or player.CharacterAdded:Wait()
        local hrp       = character:WaitForChild("HumanoidRootPart")
        local humanoid  = character:WaitForChild("Humanoid")

        setStatus("Warp ke start...")
        hrp.CFrame = CFrame.new(-343.73, 10.77, -1609.55)
        task.wait(0.5)

        -- Load & spawn vehicle
        setStatus("Load data kendaraan...")
        local dealership = game:GetService("ReplicatedStorage"):WaitForChild("DealershipEvents")
        pcall(function() dealership:WaitForChild("InitializeCarData"):InvokeServer() end)
        task.wait(0.5)
        pcall(function() dealership:WaitForChild("GetInfoCarSlot"):InvokeServer() end)
        task.wait(0.5)

        setStatus("Buka vehicle spawner...")
        local spawnButton = player.PlayerGui:WaitForChild("MainUI"):WaitForChild("Spawn"):WaitForChild("SpawnCar")
        if spawnButton then
            -- Pakai cara yg aman buat Delta Android (getconnections bisa break tombol)
            local fired = false
            if not fired then pcall(function() firesignal(spawnButton.MouseButton1Click) fired = true end) end
            if not fired then pcall(function() fireclick(spawnButton) fired = true end) end
            if not fired then pcall(function() spawnButton:Activate() end) end
        end
        task.wait(0.5)

        setStatus("Ambil list motor...")
        local scrollingFrame = player.PlayerGui:WaitForChild("MainUI"):WaitForChild("Frame"):WaitForChild("MainFrame"):WaitForChild("ScrollingFrame")
        local vehicles = {}
        for _, v in pairs(scrollingFrame:GetChildren()) do
            if v:IsA("ImageButton") then table.insert(vehicles, v.Name) end
        end

        if #vehicles == 0 then
            warn("Motor kosong, retry...")
            task.wait(1)
            continue
        end

        local chosen = vehicles[math.random(1, #vehicles)]
        setStatus("Spawn motor: " .. chosen)
        game:GetService("ReplicatedStorage"):WaitForChild("SpawnCarEvents"):WaitForChild("SpawnCar"):FireServer(chosen)
        task.wait(1.5)

        setStatus("Cari kendaraan...")
        local vehicle = nil
        for _, v in pairs(workspace:GetChildren()) do
            if v.Name:lower():find("montors") then vehicle = v end
        end
        if not vehicle then
            warn("Kendaraan ga ketemu, retry...")
            task.wait(1)
            continue
        end

        setStatus("Naik motor...")
        local seat = vehicle:FindFirstChild("DriveSeat", true)
        if not seat then
            warn("DriveSeat ga ketemu")
            task.wait(1)
            continue
        end

        hrp.CFrame = seat.CFrame + Vector3.new(0, 2, 0)
        task.wait(0.2)
        humanoid.Sit = false
        task.wait(0.1)
        seat:Sit(humanoid)
        task.wait(0.5)
        if seat.Occupant ~= humanoid then
            hrp.CFrame = seat.CFrame
            task.wait(0.2)
            seat:Sit(humanoid)
            task.wait(0.5)
        end

        local root    = vehicle:FindFirstChild("PrimaryPart") or seat
        local raceGui = player.PlayerGui:WaitForChild("RaceGui")
        local countdown = raceGui:WaitForChild("CountdownLabel")
        local lapLabel  = raceGui:WaitForChild("RaceInfoFrame"):WaitForChild("Timers"):WaitForChild("LapLabel")

        -- RACE LOOP: ulangi selama masih di motor
        local interface = player.PlayerGui:FindFirstChild("Interface")

        while true do
            local hum = character:FindFirstChild("Humanoid")
            if not hum or not hum.SeatPart then break end

            setStatus("Waiting Countdown... ⏳")
            repeat task.wait(0.1) until countdown.Visible == true
            setStatus("Countdown mulai ⏳")
            local last = lapLabel.Text
            repeat task.wait(0.1) until lapLabel.Text ~= last and string.find(lapLabel.Text, "LAP")

            -- Disable game crash/fall scripts SEBELUM race mulai
            -- supaya ga ngambil alih pas kita nyentuh garis finish
            if interface then
                pcall(function() interface:FindFirstChild("FallingScript").Disabled = true end)
                pcall(function() interface:FindFirstChild("CrashScript").Disabled  = true end)
            end

            setStatus("Racing... 🏁")
            runAI(root)

            -- Helper: cek apakah race sudah selesai
            -- Race selesai kalau: teks lapLabel ga ada "LAP", ATAU lapLabel/parent-nya invisible
            local raceFinished = false
            local function markFinished()
                if raceFinished then return end
                raceFinished = true
                _G.triggerCoast = true
            end

            local function isRaceDone()
                -- Cek teks: kalau ga ada "LAP" berarti race selesai
                if not string.find(lapLabel.Text, "LAP") then return true end
                -- Cek visibility: kalau lapLabel atau parent-nya (RaceInfoFrame) invisible
                if not lapLabel.Visible then return true end
                local raceInfoFrame = lapLabel.Parent and lapLabel.Parent.Parent
                if raceInfoFrame and not raceInfoFrame.Visible then return true end
                return false
            end

            -- Signal-based: tangkep perubahan teks
            local finishConns = {}
            table.insert(finishConns, lapLabel:GetPropertyChangedSignal("Text"):Connect(function()
                if isRaceDone() then markFinished() end
            end))
            -- Signal-based: tangkep perubahan visibility
            table.insert(finishConns, lapLabel:GetPropertyChangedSignal("Visible"):Connect(function()
                if isRaceDone() then markFinished() end
            end))
            -- Juga monitor parent visibility (RaceInfoFrame)
            pcall(function()
                local raceInfoFrame = lapLabel.Parent and lapLabel.Parent.Parent
                if raceInfoFrame and raceInfoFrame:IsA("GuiObject") then
                    table.insert(finishConns, raceInfoFrame:GetPropertyChangedSignal("Visible"):Connect(function()
                        if isRaceDone() then markFinished() end
                    end))
                end
            end)

            -- Polling fallback: cek tiap 0.25s kalau signal-based miss
            repeat
                task.wait(0.25)
                if isRaceDone() then markFinished() end
            until raceFinished or
                not (character:FindFirstChild("Humanoid") and character:FindFirstChild("Humanoid").SeatPart)

            for _, c in ipairs(finishConns) do pcall(function() c:Disconnect() end) end

            -- AI sekarang lanjut jalan ke start (isFinishing mode di runAI)
            setStatus("Kembali ke start... 🏠")
            local returnDeadline = os.clock() + 60
            while not finishedRace and (os.clock() < returnDeadline) do
                task.wait(0.25)
            end

            stopAI()

            -- Re-enable game scripts setelah aman
            if interface then
                pcall(function() interface:FindFirstChild("FallingScript").Disabled = false end)
                pcall(function() interface:FindFirstChild("CrashScript").Disabled  = false end)
            end
            
            roundCounter = roundCounter + 1
            setStatus("Selesai Round " .. roundCounter .. "/" .. MAX_ROUNDS)

            if roundCounter >= MAX_ROUNDS then
                setStatus("Rejoin ke Private Server...")
                pcall(function()
                    local teleportQueue = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
                    if teleportQueue then
                        teleportQueue('task.wait(10); loadstring(game:HttpGet("https://raw.githubusercontent.com/petinjusemarang/mobilelegend/refs/heads/main/puk.lua"))()')
                    end
                end)
                
                local ReplicatedStorage = game:GetService("ReplicatedStorage")
                local event = ReplicatedStorage:WaitForChild("PrivateServerEvents"):WaitForChild("CreatePrivateServer")
                local args = { 114862923457266 }
                
                while true do
                    pcall(function()
                        event:FireServer(unpack(args))
                        print("Create Private Server triggered")
                    end)
                    task.wait(5)
                end
            end
        end

        -- Sudah tidak di motor — cleanup lalu spawn ulang
        if activeBodyGyro then activeBodyGyro:Destroy(); activeBodyGyro = nil end
        activeRoot = nil

        setStatus("Despawn kendaraan...")
        local deleteBtn = player.PlayerGui:WaitForChild("MainUI"):WaitForChild("Despawn"):WaitForChild("DeleteCar")
        if deleteBtn then
            local fired = false
            if not fired then pcall(function() firesignal(deleteBtn.MouseButton1Click) fired = true end) end
            if not fired then pcall(function() fireclick(deleteBtn) fired = true end) end
            if not fired then pcall(function() deleteBtn:Activate() end) end
        end
        task.wait(0.2)

        setStatus("Looping... 🔁")
        task.wait(0.2)
    end
end)
