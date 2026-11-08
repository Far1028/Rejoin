-- ===================== PENGATURAN =====================
local CFG = {
	defaultTime = 10800,       -- Waktu dalam detik
	updateInterval = 0.03,     -- Seberapa sering teks timer diperbarui (detik)
	maxRetries = 5,            -- Maksimal percobaan teleport ulang kalau gagal
	retryDelay = 3,            -- Jeda antar percobaan (detik, bertambah tiap percobaan)
	teleportTimeout = 30,      -- Kalau teleport menggantung segini lama, dianggap gagal
	allowPublicFallback = false, -- true = kalau private server gagal terus, pindah ke publik
	rejoinSameServer = true,   -- true = server publik juga dicoba balik ke server yang sama
	privateServerLink = "https://www.roblox.com/share?code=ce3609af03ef75459e91e6ec57a0c795&type=Server",    -- Tempel link private server dari temanmu di antara tanda kutip
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
local linkCooldown = false
local heartbeatConn, failConn, overlayConn

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
		local val = (type(v) == "string") and string.format("%q", v) or tostring(v)
		parts[#parts + 1] = k .. "=" .. val
	end

	local lvl = 0
	while SRC:find("]" .. string.rep("=", lvl) .. "]", 1, true) do
		lvl += 1
	end
	local eq = string.rep("=", lvl)

	local code = table.concat({
		"if game.PlaceId ~= " .. tostring(placeId) .. " then return end",
		"local g = (getgenv and getgenv()) or _G",
		"g.__TimerCfg = {" .. table.concat(parts, ",") .. "}",
		"g.__TimerSrc = [" .. eq .. "[" .. SRC .. "]" .. eq .. "]",
		"loadstring(g.__TimerSrc)()",
	}, "\n")

	queued = pcall(q, code)
end

-- ===================== REJOIN LEWAT LINK PRIVATE SERVER =====================
local GuiService = game:GetService("GuiService")

local function rejoinViaLink(reason)
	if not alive or linkCooldown then return end

	local link = CFG.privateServerLink
	if type(link) ~= "string" or link == "" then
		notify("Server tidak bisa dimasuki lagi, dan privateServerLink belum diisi di pengaturan.")
		return
	end

	linkCooldown = true
	task.delay(60, function() linkCooldown = false end)

	-- Salin link supaya bisa ditempel manual kalau pembukaan otomatis gagal
	pcall(function() setclipboard(link) end)

	local opened = false
	local code = link:match("privateServerLinkCode=([%w%-_]+)")
	if code then
		opened = pcall(function()
			GuiService:OpenBrowserWindow("roblox://experiences/start?placeId=" .. tostring(placeId) .. "&linkCode=" .. code)
		end)
	end
	if not opened then
		opened = pcall(function() GuiService:OpenBrowserWindow(link) end)
	end

	notify("Link private server disalin dan dibuka. Kalau belum masuk otomatis, tempel di browser lalu tekan Join.")
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
		if isPrivate then rejoinViaLink(reason) end
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

-- ===================== DETEKSI DISCONNECT =====================
task.spawn(function()
	local ok, err = pcall(function()
		local CoreGui = game:GetService("CoreGui")
		local gui = CoreGui:WaitForChild("RobloxPromptGui", 15)
		local overlay = gui and gui:WaitForChild("promptOverlay", 15)
		if not overlay then error("promptOverlay tidak ditemukan") end

		overlayConn = overlay.ChildAdded:Connect(function(child)
			if child.Name ~= "ErrorPrompt" or not alive then return end
			if triggered then return end -- error saat teleport ditangani TeleportInitFailed

			notify("Terputus dari server.")
			task.wait(2)
			if not alive then return end

			if isPrivate then
				rejoinViaLink("disconnect")
			else
				pcall(function() TeleportService:Teleport(placeId, player) end)
			end
		end)
	end)
	if not ok then
		notify("Deteksi disconnect tidak aktif: " .. tostring(err))
	end
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
	if overlayConn then overlayConn:Disconnect() end
	if screenGui then screenGui:Destroy() end
end

genv.__TimerCleanup = cleanup
genv.TimerTestLink = function()
	linkCooldown = false
	rejoinViaLink("test")
end
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
