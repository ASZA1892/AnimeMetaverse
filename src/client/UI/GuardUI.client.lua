-- src/client/UI/GuardUI.client.lua
-- Client-side guard bar UI (optimized)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Constants = require(ReplicatedStorage.Shared.Types.constants)
local CombatActions = require(ReplicatedStorage.Shared.Types.CombatActions)
local CombatRemote = ReplicatedStorage:WaitForChild("CombatRemote")

-- Create ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GuardUI"
screenGui.Parent = playerGui

-- Create Guard Bar Frame
local barFrame = Instance.new("Frame")
barFrame.Size = UDim2.new(0, 200, 0, 20)
barFrame.Position = UDim2.new(0.5, -100, 0.8, 0)
barFrame.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
barFrame.BorderSizePixel = 0
barFrame.Parent = screenGui

-- Create fill bar
local fillBar = Instance.new("Frame")
fillBar.Size = UDim2.new(1, 0, 1, 0)
fillBar.BackgroundColor3 = Color3.new(0.2, 0.6, 1.0)
fillBar.BorderSizePixel = 0
fillBar.Parent = barFrame

-- Create text label
local textLabel = Instance.new("TextLabel")
textLabel.Size = UDim2.new(1, 0, 1, 0)
textLabel.BackgroundTransparency = 1
textLabel.Text = "Guard: 100%"
textLabel.TextColor3 = Color3.new(1, 1, 1)
textLabel.TextScaled = true
textLabel.Font = Enum.Font.GothamBold
textLabel.Parent = barFrame

-- Update bar based on guard value
local function updateGuardBar(guardValue)
    local percent = guardValue / Constants.MAX_GUARD
    fillBar.Size = UDim2.new(percent, 0, 1, 0)
    textLabel.Text = string.format("Guard: %d%%", math.floor(percent * 100))
    
    if percent > 0.5 then
        fillBar.BackgroundColor3 = Color3.new(0.2, 0.6, 1.0)
    elseif percent > 0.2 then
        fillBar.BackgroundColor3 = Color3.new(1.0, 0.8, 0.2)
    else
        fillBar.BackgroundColor3 = Color3.new(1.0, 0.2, 0.2)
    end
end

-- Initial update
updateGuardBar(Constants.MAX_GUARD)

-- Listen for guard updates
CombatRemote.OnClientEvent:Connect(function(action, data)
    if action == CombatActions.ServerToClient.GUARD_UPDATE then
        if data.player == player then
            updateGuardBar(data.guard)
        end
    elseif action == CombatActions.ServerToClient.GUARD_BROKEN then
        if data.player == player then
            updateGuardBar(0)
        end
    end
end)

print("✅ GuardUI initialized")