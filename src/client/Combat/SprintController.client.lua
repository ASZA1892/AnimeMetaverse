-- src/client/Combat/SprintController.client.lua

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Types.constants)

local player = Players.LocalPlayer
local WALK_SPEED = 16
local SPRINT_SPEED = 28
local isSprinting = false

local function dbg(...)
	if Constants.DEBUG then
		print("[SprintController]", ...)
	end
end

local function getHumanoid()
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function setSprint(state)
	local hum = getHumanoid()
	if not hum then return end
	isSprinting = state
	hum.WalkSpeed = state and SPRINT_SPEED or WALK_SPEED
	dbg("Sprint:", state, "Speed:", hum.WalkSpeed)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		setSprint(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		setSprint(false)
	end
end)

-- Reset on respawn
player.CharacterAdded:Connect(function(char)
	isSprinting = false
	local hum = char:WaitForChild("Humanoid")
	hum.WalkSpeed = WALK_SPEED
end)

print("✅ SprintController initialized")