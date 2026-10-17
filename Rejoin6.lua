-- [SYSTEM: SECURE PRIVATE SERVER RECONNECTOR]
local defaultTime = 10800 -- Waktu dalam detik (3 Jam)
local targetPlaceId = game.PlaceId
local serverShareCode = "25f5212ea6d1ae479f7b414fffac7fa2"

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BSSTerminalTimer"
screenGui.Parent = player:WaitForChild("PlayerGui")
screenGui.ResetOnSpawn = false

local timerFrame = Instance.new("Frame")
timerFrame.Size = UDim2.new(0, 260, 0, 185)
timerFrame.Position = UDim2.new(0.5, -130, 0.4, -92)
timerFrame.BackgroundColor3 = Color3.fromRGB(13, 17, 23)
timerFrame.BorderSizePixel = 1
timerFrame.BorderColor3 = Color3.fromRGB(0, 255, 128)
timerFrame.Active = true
timerFrame.Draggable = true
timerFrame.Parent = screenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 4)
UICorner.Parent = timerFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 26)
Title.BackgroundColor3 = Color3.fromRGB(22, 27, 34)
Title.TextColor3 = Color3.fromRGB(0, 255, 128)
Title.Text = "> server_timer_sync.lua"
Title.TextSize = 10
Title.Font = Enum.Font.Code
Title.Parent = timerFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 4)
TitleCorner.Parent = Title

-- Tampilan Hitung Mundur Utama di dalam GUI
local timerLabel = Instance.new("TextLabel")
timerLabel.Size = UDim2.new(0.88, 0, 0, 40)
timerLabel.Position = UDim2.new(0.06, 0, 0, 40)
timerLabel.BackgroundColor3 = Color3.fromRGB(1, 4, 9)
timerLabel.TextColor3 = Color3.fromRGB(0, 255, 128)
timerLabel.Text = "03:00:00.00"
timerLabel.TextSize = 16
timerLabel.Font = Enum.Font.Code
timerLabel.Parent = timerFrame

local timerCorner = Instance.new("UICorner")
timerCorner.CornerRadius = UDim.new(0, 3)
timerCorner.Parent = timerLabel

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(0.88, 0, 0, 25)
StatusLabel.Position = UDim2.new(0.06, 0, 0, 90)
StatusLabel.BackgroundTransparency = 1
StatusLabel.TextColor3 = Color3.fromRGB(255, 166, 87)
StatusLabel.Text = "status: timer active..."
StatusLabel.TextSize = 9
StatusLabel.Font = Enum.Font.Code
StatusLabel.TextWrapped = true
StatusLabel.Parent = timerFrame

-- Tombol Status / Manual Reconnect
local ActionBtn = Instance.new("TextButton")
ActionBtn.Size = UDim2.new(0.88, 0, 0, 28)
ActionBtn.Position = UDim2.new(0.06, 0, 0, 125)
ActionBtn.BackgroundColor3 = Color3.fromRGB(35, 134, 54)
ActionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ActionBtn.Text = "[ PRIVATE SERVER SYNCED ]"
ActionBtn.TextSize = 9
ActionBtn.Font = Enum.Font.Code
ActionBtn.Parent = timerFrame

local ActionCorner = Instance.new("UICorner")
ActionCorner.CornerRadius = UDim.new(0, 3)
ActionCorner.Parent = ActionBtn

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 22, 0, 22)
CloseBtn.Position = UDim2.new(1, -25, 0, 2)
CloseBtn.BackgroundColor3 = Color3.fromRGB(248, 81, 73)
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Text = "x"
CloseBtn.TextSize = 10
CloseBtn.Font = Enum.Font.Code
CloseBtn.Parent = MainFrame or timerFrame
CloseBtn.Parent = timerFrame

CloseBtn.MouseButton1Click:Connect(function()
	screenGui:Destroy()
end)

-- Format waktu (Jam:Menit:Detik.Milidetik)
local function formatTime(totalSeconds)
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	local seconds = math.floor(totalSeconds % 60)
	local milliseconds = math.floor((totalSeconds - math.floor(totalSeconds)) * 100)

	return string.format("%02d:%02d:%02d.%02d", hours, minutes, seconds, milliseconds)
end

local startTime = os.clock()
local targetTime = startTime + defaultTime

timerLabel.Text = formatTime(defaultTime)

-- Fungsi Eksekusi Teleport ke Private Server
local function executeTeleport()
	StatusLabel.Text = "status: reconnecting to private server..."
	pcall(function()
		-- Menggunakan JobId aktif saat ini untuk kembali ke server privat yang sama secara instan dan mulus
		TeleportService:TeleportToPlaceInstance(targetPlaceId, game.JobId, player)
	end)
end

ActionBtn.MouseButton1Click:Connect(function()
	executeTeleport()
end)

-- Loop Countdown Berjalan di Background
local connection
connection = RunService.Heartbeat:Connect(function()
	local timeLeft = math.max(0, targetTime - os.clock())

	timerLabel.Text = formatTime(timeLeft)

	if timeLeft <= 0 then
		connection:Disconnect()
		executeTeleport()
	end
end)
