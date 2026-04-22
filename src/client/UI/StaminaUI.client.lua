-- src/client/UI/StaminaUI.client.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Constants = require(ReplicatedStorage.Shared.Types.constants)

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local staminaStateModule = sharedFolder:WaitForChild("StaminaState", 10)
if not staminaStateModule then
	error("StaminaState module not found at ReplicatedStorage.Shared.StaminaState")
end

local StaminaState = require(staminaStateModule)
if type(StaminaState.GetStamina) ~= "function" then
	error("StaminaState.GetStamina() is missing")
end

local MAX_STAMINA = Constants.MAX_STAMINA or 100
local POLL_INTERVAL = 0.1
local TWEEN_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StaminaUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local barBackground = Instance.new("Frame")
barBackground.Name = "BarBackground"
barBackground.AnchorPoint = Vector2.new(0.5, 1)
barBackground.Position = UDim2.fromScale(0.5, 0.93)
barBackground.Size = UDim2.fromOffset(320, 24)
barBackground.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
barBackground.BorderSizePixel = 0
barBackground.Parent = screenGui

local backgroundCorner = Instance.new("UICorner")
backgroundCorner.CornerRadius = UDim.new(0, 6)
backgroundCorner.Parent = barBackground

local fillBar = Instance.new("Frame")
fillBar.Name = "FillBar"
fillBar.AnchorPoint = Vector2.new(0, 0)
fillBar.Position = UDim2.fromScale(0, 0)
fillBar.Size = UDim2.fromScale(1, 1)
fillBar.BackgroundColor3 = Color3.fromRGB(255, 218, 41)
fillBar.BorderSizePixel = 0
fillBar.Parent = barBackground

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 6)
fillCorner.Parent = fillBar

local staminaText = Instance.new("TextLabel")
staminaText.Name = "StaminaText"
staminaText.AnchorPoint = Vector2.new(0.5, 0.5)
staminaText.Position = UDim2.fromScale(0.5, 0.5)
staminaText.Size = UDim2.fromScale(1, 1)
staminaText.BackgroundTransparency = 1
staminaText.TextColor3 = Color3.fromRGB(20, 20, 20)
staminaText.TextStrokeTransparency = 0.8
staminaText.Font = Enum.Font.GothamBold
staminaText.TextScaled = true
staminaText.Parent = barBackground

local currentTween
local lastShownStamina = -1

local function updateStaminaDisplay(rawStamina)
	local stamina = math.clamp(tonumber(rawStamina) or 0, 0, MAX_STAMINA)
	local ratio = stamina / MAX_STAMINA

	if currentTween then
		currentTween:Cancel()
	end

	currentTween = TweenService:Create(fillBar, TWEEN_INFO, {
		Size = UDim2.fromScale(ratio, 1),
	})
	currentTween:Play()

	staminaText.Text = string.format("%d / %d", math.floor(stamina + 0.5), MAX_STAMINA)
end

task.spawn(function()
	while true do
		local ok, staminaValue = pcall(StaminaState.GetStamina)
		if ok then
			local normalized = tonumber(staminaValue) or 0
			if normalized ~= lastShownStamina then
				lastShownStamina = normalized
				updateStaminaDisplay(normalized)
			end
		end
		task.wait(POLL_INTERVAL)
	end
end)
