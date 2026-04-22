-- src/client/Combat/SubstitutionController.client.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local CombatRemote = ReplicatedStorage:WaitForChild("CombatRemote", 10)
if not CombatRemote then
	error("CombatRemote not found")
end

local CombatActions = require(ReplicatedStorage.Shared.Types.CombatActions)
local Constants = require(ReplicatedStorage.Shared.Types.constants)
local StaminaState = require(ReplicatedStorage.Shared.StaminaState)

local SUBSTITUTION_MIN_STAMINA = Constants.SUBSTITUTION_MIN_STAMINA or 20
local SUBSTITUTION_COST = 20
local SUBSTITUTION_INPUT_WINDOW = 0.3
local SUBSTITUTION_COOLDOWN = 8
local TELEPORT_BEHIND_DISTANCE = 8

local lastQPressedAt = -math.huge
local lastSubstitutionAt = -math.huge

local flashGui
local flashFrame

local function debugPrint(...)
	if Constants.DEBUG then
		print("[SubstitutionController]", ...)
	end
end

local function ensureFlashGui()
	if flashGui and flashGui.Parent and flashFrame and flashFrame.Parent then
		return flashFrame
	end

	flashGui = Instance.new("ScreenGui")
	flashGui.Name = "SubstitutionFlashGui"
	flashGui.ResetOnSpawn = false
	flashGui.IgnoreGuiInset = true
	flashGui.DisplayOrder = 1000

	flashFrame = Instance.new("Frame")
	flashFrame.Name = "Flash"
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.Position = UDim2.fromScale(0, 0)
	flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	flashFrame.BorderSizePixel = 0
	flashFrame.BackgroundTransparency = 1
	flashFrame.Parent = flashGui

	local playerGui = player:WaitForChild("PlayerGui")
	flashGui.Parent = playerGui

	return flashFrame
end

local function playFlash()
	local frame = ensureFlashGui()
	frame.BackgroundTransparency = 0.75

	local tween = TweenService:Create(
		frame,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	tween:Play()
end

local function getCharacterAndRoot()
	local character = player.Character
	if not character then return nil, nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	return character, root
end

local function canSubstituteNow()
	local now = tick()

	if (now - lastQPressedAt) > SUBSTITUTION_INPUT_WINDOW then
		debugPrint("Blocked: Q input window expired")
		return false
	end

	local stamina = StaminaState.GetStamina()
	if stamina <= SUBSTITUTION_MIN_STAMINA then
		debugPrint("Blocked: stamina must be above minimum", stamina, "min=", SUBSTITUTION_MIN_STAMINA)
		return false
	end

	if (now - lastSubstitutionAt) < SUBSTITUTION_COOLDOWN then
		debugPrint("Blocked: cooldown active", SUBSTITUTION_COOLDOWN - (now - lastSubstitutionAt))
		return false
	end

	return true
end

local function extractPositionFromData(data)
	if typeof(data) ~= "table" then
		return nil
	end

	local attackerPosition = data.attackerPosition or data.position
	if typeof(attackerPosition) == "Vector3" then
		return attackerPosition
	end

	if typeof(attackerPosition) == "table" then
		local x = tonumber(attackerPosition.x)
		local y = tonumber(attackerPosition.y)
		local z = tonumber(attackerPosition.z)
		if x and y and z then
			return Vector3.new(x, y, z)
		end
	end

	local attacker = data.attacker
	if typeof(attacker) == "Instance" and attacker:IsA("Player") and attacker.Character then
		local root = attacker.Character:FindFirstChild("HumanoidRootPart")
		if root then
			return root.Position
		end
	end

	return nil
end

local function attemptSubstitution(hitData)
	if typeof(hitData) == "table" then
		if hitData.attacker == player then
			debugPrint("Ignored HIT_CONFIRMED: local player is attacker")
			return
		end
		if hitData.target and hitData.target ~= player then
			debugPrint("Ignored HIT_CONFIRMED: local player is not target")
			return
		end
	end

	if not canSubstituteNow() then
		return
	end

	CombatRemote:FireServer(CombatActions.ClientToServer.SUBSTITUTION, hitData)
	StaminaState.Deduct(SUBSTITUTION_COST)
	lastSubstitutionAt = tick()

	debugPrint("Substitution requested", "stamina=", StaminaState.GetStamina())
end

local function handleSubstitutionConfirmed(data)
	local _, root = getCharacterAndRoot()
	if not root then
		debugPrint("Teleport skipped: no humanoid root part")
		return
	end

	local attackerPosition = extractPositionFromData(data)
	if not attackerPosition then
		debugPrint("Teleport skipped: attacker position missing")
		return
	end

	local currentPos = root.Position
	local horizontalDelta = Vector3.new(currentPos.X - attackerPosition.X, 0, currentPos.Z - attackerPosition.Z)
	local fallbackForward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if fallbackForward.Magnitude == 0 then
		fallbackForward = Vector3.new(0, 0, -1)
	end
	local behindDir = horizontalDelta.Magnitude > 0 and horizontalDelta.Unit or fallbackForward.Unit
	local destination = attackerPosition + (behindDir * TELEPORT_BEHIND_DISTANCE)

	root.CFrame = CFrame.new(destination, attackerPosition)
	playFlash()

	debugPrint("Substitution confirmed: teleported behind attacker")
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.Q then
		lastQPressedAt = tick()
		debugPrint("Q pressed at", lastQPressedAt)
	end
end)

CombatRemote.OnClientEvent:Connect(function(action, data)
	if action == CombatActions.ServerToClient.HIT_CONFIRMED then
		attemptSubstitution(data)
		return
	end

	if action == CombatActions.ServerToClient.SUBSTITUTION_CONFIRMED then
		handleSubstitutionConfirmed(data)
		return
	end
end)

debugPrint("SubstitutionController initialized")
