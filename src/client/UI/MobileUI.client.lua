local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not UserInputService.TouchEnabled then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CombatRemote = ReplicatedStorage:WaitForChild("CombatRemote")
local CombatActions = require(ReplicatedStorage.Shared.Types.CombatActions)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MobileCombatUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local attackButton = Instance.new("TextButton")
attackButton.Name = "AttackButton"
attackButton.Size = UDim2.fromOffset(80, 80)
attackButton.Position = UDim2.new(1, -100, 1, -120)
attackButton.AnchorPoint = Vector2.new(0, 0)
attackButton.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
attackButton.TextColor3 = Color3.new(1, 1, 1)
attackButton.TextScaled = true
attackButton.Font = Enum.Font.GothamBold
attackButton.Text = "Attack"
attackButton.AutoButtonColor = true
attackButton.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = attackButton

attackButton.Activated:Connect(function()
	CombatRemote:FireServer(CombatActions.ClientToServer.M1_ATTACK, {
		moveId = "Jab",
	})
end)
