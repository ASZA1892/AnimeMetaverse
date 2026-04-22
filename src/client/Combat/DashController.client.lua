-- src/client/Combat/DashController.client.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatRemote = ReplicatedStorage:WaitForChild("CombatRemote", 10)
if not CombatRemote then
	error("CombatRemote not found")
end

local CombatActions = require(ReplicatedStorage.Shared.Types.CombatActions)
local Constants = require(ReplicatedStorage.Shared.Types.constants)
local StaminaState = require(ReplicatedStorage.Shared.StaminaState)

local player = Players.LocalPlayer

local lastDashAt = 0
local dashCooldown = Constants.DASH_COOLDOWN or 0.8
local quickDashStaminaCost = Constants.DASH_STAMINA_QUICK or 10

local DASH_CONFIRMED_ACTION = (CombatActions.ServerToClient and CombatActions.ServerToClient.DASH_CONFIRMED) or "DashConfirmed"

local function debugPrint(...)
	if Constants.DEBUG then
		print("[DashController]", ...)
	end
end

local function getDashDirection()
	local character = player.Character
	if not character then return Vector3.zero end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return Vector3.zero end

	local w = UserInputService:IsKeyDown(Enum.KeyCode.W)
	local s = UserInputService:IsKeyDown(Enum.KeyCode.S)
	local a = UserInputService:IsKeyDown(Enum.KeyCode.A)
	local d = UserInputService:IsKeyDown(Enum.KeyCode.D)
	local strafe = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)

	if not w and not s and not a and not d then
		return root.CFrame.LookVector
	end

	if strafe then
		local vec = Vector3.zero
		if w then vec = vec + root.CFrame.LookVector end
		if s then vec = vec - root.CFrame.LookVector end
		if a then vec = vec - root.CFrame.RightVector end
		if d then vec = vec + root.CFrame.RightVector end
		if vec.Magnitude > 0 then
			return vec.Unit
		end
		return root.CFrame.LookVector
	end

	local camera = Workspace.CurrentCamera
	if not camera then return root.CFrame.LookVector end

	local camLook = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	local camRight = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)

	if camLook.Magnitude > 0 then camLook = camLook.Unit end
	if camRight.Magnitude > 0 then camRight = camRight.Unit end

	local moveVec = Vector3.zero
	if w then moveVec = moveVec + camLook end
	if s then moveVec = moveVec - camLook end
	if a then moveVec = moveVec - camRight end
	if d then moveVec = moveVec + camRight end

	if moveVec.Magnitude > 0 then
		return moveVec.Unit
	end
	return root.CFrame.LookVector
end

local function canQuickDash()
	local now = tick()
	if (now - lastDashAt) < dashCooldown then
		debugPrint("Dash blocked: cooldown active")
		return false
	end
	if StaminaState.GetStamina() < quickDashStaminaCost then
		debugPrint("Dash blocked: not enough stamina", StaminaState.GetStamina(), "/", quickDashStaminaCost)
		return false
	end
	return true
end

local function applyClientDashVisual(directionVec, dashData)
	local character = player.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local dashDir = directionVec
	if typeof(dashDir) ~= "Vector3" then
		dashDir = root.CFrame.LookVector
	end

	local speed = (dashData and dashData.speed) or 80
	local duration = (dashData and dashData.duration) or 0.15

	local currentVelocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(
		dashDir.X * speed,
		currentVelocity.Y,
		dashDir.Z * speed
	)

	task.delay(duration, function()
		if root and root.Parent then
			local vel = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
		end
	end)

	debugPrint("Dash visual applied, speed=", speed)
end

local function attemptQuickDash()
	if not canQuickDash() then return end

	local direction = getDashDirection()

	StaminaState.Deduct(quickDashStaminaCost)
	lastDashAt = tick()

	applyClientDashVisual(direction, { speed = 80, duration = 0.15 })

	local dirData = { x = direction.X, y = direction.Y, z = direction.Z }

	CombatRemote:FireServer(CombatActions.ClientToServer.DASH, {
		direction = dirData,
		dashType = "quick",
		clientSentAt = tick(),
	})

	debugPrint("Fired DASH | stamina=", StaminaState.GetStamina())
end

-- Stamina regeneration loop
task.spawn(function()
	while true do
		task.wait(0.1)
		StaminaState.Regen((Constants.STAMINA_REGEN_RATE or 15) * 0.1)
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Q then
		attemptQuickDash()
	end
end)

CombatRemote.OnClientEvent:Connect(function(action, data)
	if action ~= DASH_CONFIRMED_ACTION then return end
end)

debugPrint("DashController initialized")