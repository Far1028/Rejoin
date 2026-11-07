-- ===================== PENGATURAN =====================
local CFG = {
	defaultTime = 10800,       -- Waktu dalam detik
	updateInterval = 0.03,     -- Seberapa sering teks timer diperbarui (detik)
	maxRetries = 5,            -- Maksimal percobaan teleport ulang kalau gagal
	retryDelay = 3,            -- Jeda antar percobaan (detik, bertambah tiap percobaan)
	teleportTimeout = 30,      -- Kalau teleport menggantung segini lama, dianggap gagal
	allowPublicFallback = false, -- true = kalau private server gagal terus, pindah ke publik
	rejoinSameServer = true,   -- true = server publik juga dicoba balik ke server yang sama
	warn1 = 60,                -- Notifikasi peringatan pertama (detik sebelum teleport)
	warn2 = 10,                -- Notifikasi peringatan kedua
}
-- =======================================================

local SRC = [==[
local genv = (getgenv and getgenv()) or _G
local CFG = genv.__TimerCfg
local SRC = genv.__TimerSrc

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Hapus instance lama kalau script dijalankan dua kali
if genv.__TimerCleanup then pcall(genv.__TimerCleanup) end
local oldGui = playerGui:FindFirstChild("TeleportTimerGui")
if oldGui then oldGui:Destroy() end

-- ===================== UI (sama seperti aslinya) =====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TeleportTimerGui"
screenGui.Parent = playerGui
screenGui.ResetOnSpawn = false

local timerFrame = Instance.new("Frame")
timerFrame.Size = UDim2.new(0, 200, 0, 50)
timerFrame.Position = UDim2.new(1, -210, 1, -60)
timerFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
timerFrame.BackgroundTransparency = 0.4
timerFrame.Parent = screenGui

local timerFrameCorner = Instance.new("UICorner")
timerFrameCorner.CornerRadius = UDim.new(0, 12)
timerFrameCorner.Parent = timerFrame

local timerLabel = Instance.new("TextLabel")
timerLabel.Size = UDim2.new(1, 0, 1, 0)
timerLabel.BackgroundTransparency = 1
timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
timerLabel.TextSize = 18
timerLabel.Text = "0:00:00.00"
timerLabel.Parent = timerFrame
-- =====================================================================

local function formatTime(totalSeconds)
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	local seconds = math.floor(totalSeconds % 60)
	local milliseconds = math.floor((totalSeconds - math.floor(totalSeconds)) * 100)
	return string.format("%d:%02d:%02d.%02d", hours, minutes, seconds, milliseconds)
end

local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Auto Rejoin Timer",
			Text = text,
			Duration = 6,
		})
	end)
end

-- Waktu dinding (tetap jalan walau game lag / app di background)
local function now()
	return DateTime.now().UnixTimestampMillis / 1000
end

-- ===================== STATE =====================
local placeId = game.PlaceId
local jobId = game.JobId
local isPrivate = game.PrivateServerId ~= ""
local sameServer = isPrivate or CFG.rejoinSameServer

local alive = true
local targetTime = 0
local triggered = false
local teleporting = false
local retryPending = false
local queued = false
local attempts = 0
local notified = {}
local lastUpdate = 0
local heartbeatConn, failConn

-- ===================== QUEUE SCRIPT KE SERVER BERIKUTNYA =====================
local function queueSelf()
	if queued then return end
	local q = queue_on_teleport
		or (syn and syn.queue_on_teleport)
		or queueonteleport
		or (fluxus and fluxus.queue_on_teleport)
	if not q then
		notify("Executor tidak mendukung queue_on_teleport. Taruh script di folder autoexec.")
		queued = true
		return
	end

	local parts = {}
	for k, v in pairs(CFG) do
		parts[#parts + 1] = k .. "=" .. tostring(v)
	end

	local code = table.concat({
		"if game.PlaceId ~= " .. tostring(placeId) .. " then return end",
		"local g = (getgenv and getgenv()) or _G",
		"g.__TimerCfg = {" .. table.concat(parts, ",") .. "}",
		"g.__TimerSrc = [==[" .. SRC .. "]==]",
		"loadstring(g.__TimerSrc)()",
	}, "\n")

	queued = pcall(q, code)
end

-- ===================== TELEPORT + RETRY =====================
local attemptTeleport

local function handleFail(reason)
	if not alive or retryPending then return end

	if attempts >= CFG.maxRetries then
		if sameServer and (not isPrivate or CFG.allowPublicFallback) then
			sameServer = false
			attempts = 0
			notify("Gagal kembali ke server yang sama. Pindah ke server publik...")
			retryPending = true
			task.delay(2, function()
				retryPending = false
				if alive then attemptTeleport() end
			end)
			return
		end
		notify("Teleport gagal " .. attempts .. "x (" .. tostring(reason) .. "). Berhenti mencoba.")
		return
	end

	local delayTime = CFG.retryDelay * attempts
	notify("Teleport gagal, coba lagi dalam " .. delayTime .. " detik...")
	retryPending = true
	task.delay(delayTime, function()
		retryPending = false
		if alive and not teleporting then attemptTeleport() end
	end)
end

attemptTeleport = function()
	if not alive or teleporting then return end
	attempts += 1
	teleporting = true
	local myAttempt = attempts

	queueSelf()

	local ok, err = pcall(function()
		if sameServer then
			-- Kembali ke server yang sama (JobId sama)
			TeleportService:TeleportToPlaceInstance(placeId, jobId, player)
		else
			TeleportService:Teleport(placeId, player)
		end
	end)

	if not ok then
		teleporting = false
		handleFail(err)
		return
	end

	-- Kalau teleport menggantung tanpa hasil
	task.delay(CFG.teleportTimeout, function()
		if alive and teleporting and attempts == myAttempt then
			teleporting = false
			handleFail("timeout")
		end
	end)
end

failConn = TeleportService.TeleportInitFailed:Connect(function(plr, result, msg)
	if plr ~= player then return end
	teleporting = false
	handleFail(tostring(result) .. " - " .. tostring(msg))
end)

-- ===================== TIMER =====================
local function startTimer(seconds)
	targetTime = now() + seconds
	triggered = false
	teleporting = false
	retryPending = false
	attempts = 0
	notified = {}
	timerLabel.Text = formatTime(seconds)
end

heartbeatConn = RunService.Heartbeat:Connect(function()
	if not alive then return end

	local clock = os.clock()
	if clock - lastUpdate < CFG.updateInterval then return end
	lastUpdate = clock

	local timeLeft = math.max(0, targetTime - now())
	timerLabel.Text = formatTime(timeLeft)

	for _, mark in ipairs({ CFG.warn1, CFG.warn2 }) do
		if timeLeft > 0 and timeLeft <= mark and not notified[mark] then
			notified[mark] = true
			notify("Teleport dalam " .. mark .. " detik")
		end
	end

	if timeLeft <= 0 and not triggered then
		triggered = true
		attemptTeleport()
	end
end)

-- ===================== KONTROL (bisa dipanggil dari executor) =====================
local function cleanup()
	alive = false
	if heartbeatConn then heartbeatConn:Disconnect() end
	if failConn then failConn:Disconnect() end
	if screenGui then screenGui:Destroy() end
end

genv.__TimerCleanup = cleanup
genv.TimerStop = function()
	cleanup()
	notify("Timer dihentikan")
end
genv.TimerReset = function(seconds)
	startTimer(seconds or CFG.defaultTime)
	notify("Timer di-reset")
end

startTimer(CFG.defaultTime)
]==]

-- Jalankan
local genv = (getgenv and getgenv()) or _G
genv.__TimerCfg = CFG
genv.__TimerSrc = SRC
loadstring(SRC)()
