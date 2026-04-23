-- src/client/UI/MobileUI.client.lua

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Only run on mobile
if not UserInputService.TouchEnabled then return end

local CombatRemote = ReplicatedStorage:WaitForChild("CombatRemote", 10)
local CombatActions = require(ReplicatedStorage.Shared.Types.CombatActions)
local StaminaState = require(ReplicatedStorage.Shared.StaminaState)
local Constants = require(ReplicatedStorage.Shared.Types.constants)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MobileUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Attack button
local attackBtn = Instance.new("TextButton")
attackBtn.Name = "AttackButton"
attackBtn.AnchorPoint = Vector2.new(1, 1)
attackBtn.Position = UDim2.new(1, -20, 1, -80)
attackBtn.Size = UDim2.fromOffset(90, 90)
attackBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
attackBtn.BorderSizePixel = 0
attackBtn.Text = "ATK"
attackBtn.TextColor3 = Color3.new(1, 1, 1)
attackBtn.Font = Enum.Font.GothamBold
attackBtn.TextScaled = true
attackBtn.Parent = screenGui

local attackCorner = Instance.new("UICorner")
attackCorner.CornerRadius = UDim.new(1, 0)
attackCorner.Parent = attackBtn

-- Dash button
local dashBtn = Instance.new("TextButton")
dashBtn.Name = "DashButton"
dashBtn.AnchorPoint = Vector2.new(1, 1)
dashBtn.Position = UDim2.new(1, -130, 1, -80)
dashBtn.Size = UDim2.fromOffset(70, 70)
dashBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 220)
dashBtn.BorderSizePixel = 0
dashBtn.Text = "DASH"
dashBtn.TextColor3 = Color3.new(1, 1, 1)
dashBtn.Font = Enum.Font.GothamBold
dashBtn.TextScaled = true
dashBtn.Parent = screenGui

local dashCorner = Instance.new("UICorner")
dashCorner.CornerRadius = UDim.new(1, 0)
dashCorner.Parent = dashBtn

-- Block button
local blockBtn = Instance.new("TextButton")
blockBtn.Name = "BlockButton"
blockBtn.AnchorPoint = Vector2.new(1, 1)
blockBtn.Position = UDim2.new(1, -20, 1, -190)
blockBtn.Size = UDim2.fromOffset(70, 70)
blockBtn.BackgroundColor3 = Color3.fromRGB(60, 180, 60)
blockBtn.BorderSizePixel = 0
blockBtn.Text = "BLK"
blockBtn.TextColor3 = Color3.new(1, 1, 1)
blockBtn.Font = Enum.Font.GothamBold
blockBtn.TextScaled = true
blockBtn.Parent = screenGui

local blockCorner = Instance.new("UICorner")
blockCorner.CornerRadius = UDim.new(1, 0)
blockCorner.Parent = blockBtn

-- Grab button
local grabBtn = Instance.new("TextButton")
grabBtn.Name = "GrabButton"
grabBtn.AnchorPoint = Vector2.new(1, 1)
grabBtn.Position = UDim2.new(1, -130, 1, -190)
grabBtn.Size = UDim2.fromOffset(70, 70)
grabBtn.BackgroundColor3 = Color3.fromRGB(180, 120, 30)
grabBtn.BorderSizePixel = 0
grabBtn.Text = "GRB"
grabBtn.TextColor3 = Color3.new(1, 1, 1)
grabBtn.Font = Enum.Font.GothamBold
grabBtn.TextScaled = true
grabBtn.Parent = screenGui

local grabCorner = Instance.new("UICorner")
grabCorner.CornerRadius = UDim.new(1, 0)
grabCorner.Parent = grabBtn

-- Button press visual feedback
local function flashButton(btn)
	local original = btn.BackgroundTransparency
	btn.BackgroundTransparency = 0.4
	task.delay(0.1, function()
		btn.BackgroundTransparency = original
	end)
end

-- Attack
attackBtn.TouchTap:Connect(function()
	flashButton(attackBtn)
	CombatRemote:FireServer(CombatActions.ClientToServer.M1_ATTACK, {
		clientSentAt = tick(),
		moveId = "Jab",
		aimPosition = player.Character and player.Character.PrimaryPart and player.Character.PrimaryPart.Position or Vector3.zero,
	})
end)

-- Dash
local lastDashAt = 0
dashBtn.TouchTap:Connect(function()
	local now = tick()
	if now - lastDashAt < (Constants.DASH_COOLDOWN or 0.5) then return end
	if StaminaState.GetStamina() < (Constants.DASH_STAMINA_QUICK or 10) then return end
	lastDashAt = now
	StaminaState.Deduct(Constants.DASH_STAMINA_QUICK or 10)
	flashButton(dashBtn)
	CombatRemote:FireServer(CombatActions.ClientToServer.DASH, {
		direction = { x = 0, y = 0, z = -1 },
		dashType = "quick",
		clientSentAt = now,
	})
end)

-- Block
local isBlocking = false
blockBtn.TouchTapStarted:Connect(function()
	isBlocking = true
	flashButton(blockBtn)
	CombatRemote:FireServer(CombatActions.ClientToServer.BLOCK_START)
	CombatRemote:FireServer(CombatActions.ClientToServer.PARRY)
end)

blockBtn.TouchTapEnded:Connect(function()
	if isBlocking then
		isBlocking = false
		CombatRemote:FireServer(CombatActions.ClientToServer.BLOCK_END)
	end
end)

-- Grab
grabBtn.TouchTap:Connect(function()
	flashButton(grabBtn)
	CombatRemote:FireServer(CombatActions.ClientToServer.GRAB_ATTEMPT)
end)

print("✅ MobileUI initialized")