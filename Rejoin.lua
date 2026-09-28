local defaultTime = 14400 -- Waktu dalam detik

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer

local screenGui = Instance.new("ScreenGui")
screenGui.Parent = player:WaitForChild("PlayerGui")
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

-- Format waktu (Sama seperti script asli)
local function formatTime(totalSeconds)
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	local seconds = math.floor(totalSeconds % 60)
	local milliseconds = math.floor((totalSeconds - math.floor(totalSeconds)) * 100)

	return string.format("%d:%02d:%02d.%02d", hours, minutes, seconds, milliseconds)
end

-- Countdown otomatis
local startTime = os.clock()
local targetTime = startTime + defaultTime

timerLabel.Text = formatTime(defaultTime)

local connection
connection = RunService.Heartbeat:Connect(function()
	local timeLeft = math.max(0, targetTime - os.clock())

	timerLabel.Text = formatTime(timeLeft)

	if timeLeft <= 0 then
		connection:Disconnect()

		TeleportService:Teleport(game.PlaceId, player)
	end
end)
