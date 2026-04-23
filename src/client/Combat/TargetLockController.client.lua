-- src/client/Combat/TargetLockController.client.lua

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Types.constants)

local LOCAL_PLAYER = Players.LocalPlayer
local LOCK_KEY = Enum.KeyCode.T
local SEARCH_RANGE = 30
local BREAK_RANGE = 40
local CAMERA_OFFSET = Vector3.new(0, 2.75, 12)
local MIN_PITCH = math.rad(-35)
local MAX_PITCH = math.rad(35)
local PITCH_SENSITIVITY = 0.004

local isLocked = false
local lockedPlayer = nil
local targetIndicator = nil
local pitchAngle = 0
local savedCameraType = nil
local savedCameraSubject = nil

local heartbeatConnection = nil
local deathConnection = nil

local function debugPrint(...)
	if Constants.DEBUG then
		print("[TargetLockController]", ...)
	end
end

local function disconnectConnection(connection)
	if connection then
		connection:Disconnect()
	end
end

local function getCharacterParts(player)
	if not player then return nil, nil end
	local character = player.Character
	if not character then return nil, nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then return nil, nil end
	return root, humanoid
end

local function destroyIndicator()
	if targetIndicator then
		targetIndicator:Destroy()
		targetIndicator = nil
	end
end

local function createIndicatorForTarget(targetCharacter)
	destroyIndicator()
	if not targetCharacter then return end

	local head = targetCharacter:FindFirstChild("Head")
	if not head then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TargetLockIndicator"
	billboard.Adornee = head
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(40, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
	billboard.LightInfluence = 0
	billboard.Parent = head

	local circle = Instance.new("Frame")
	circle.Name = "Circle"
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.5)
	circle.Size = UDim2.fromOffset(20, 20)
	circle.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
	circle.BorderSizePixel = 0
	circle.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = circle

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.fromScale(0.5, 1.4)
	arrow.Size = UDim2.fromOffset(20, 20)
	arrow.Font = Enum.Font.GothamBold
	arrow.Text = "▼"
	arrow.TextColor3 = Color3.fromRGB(255, 80, 80)
	arrow.TextScaled = true
	arrow.Parent = billboard

	targetIndicator = billboard
end

local function findNearestTarget(maxRange)
	local myRoot = getCharacterParts(LOCAL_PLAYER)
	if not myRoot then return nil end

	local nearestPlayer = nil
	local nearestDistance = maxRange

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LOCAL_PLAYER then
			local targetRoot, targetHumanoid = getCharacterParts(player)
			if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
				local distance = (myRoot.Position - targetRoot.Position).Magnitude
				if distance <= nearestDistance then
					nearestDistance = distance
					nearestPlayer = player
				end
			end
		end
	end

	return nearestPlayer
end

local function tweenCameraTo(cframeTarget, duration)
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local tween = TweenService:Create(
		camera,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = cframeTarget }
	)
	tween:Play()
end

local function clearLockState()
	isLocked = false
	lockedPlayer = nil
	pitchAngle = 0
	destroyIndicator()

	disconnectConnection(heartbeatConnection)
	heartbeatConnection = nil

	disconnectConnection(deathConnection)
	deathConnection = nil

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = savedCameraType or Enum.CameraType.Custom
		if savedCameraSubject then
			camera.CameraSubject = savedCameraSubject
		end
	end

	savedCameraType = nil
	savedCameraSubject = nil
end

local function unlockTarget(reason)
	if not isLocked then return end
	debugPrint("Unlocking target:", reason or "no reason")

	local camera = Workspace.CurrentCamera
	if camera then
		local myRoot = getCharacterParts(LOCAL_PLAYER)
		if myRoot then
			local releaseCFrame = CFrame.new(
				myRoot.Position - myRoot.CFrame.LookVector * 8 + Vector3.new(0, 3, 0),
				myRoot.Position + myRoot.CFrame.LookVector * 10
			)
			tweenCameraTo(releaseCFrame, 0.2)
		end
	end

	task.delay(0.21, function()
		clearLockState()
	end)
end

local function updateLockStep()
	if not isLocked then return end

	local myRoot, myHumanoid = getCharacterParts(LOCAL_PLAYER)
	local targetRoot, targetHumanoid = getCharacterParts(lockedPlayer)

	if not myRoot or not myHumanoid or not targetRoot or not targetHumanoid then
		unlockTarget("missing character parts")
		return
	end

	if targetHumanoid.Health <= 0 then
		unlockTarget("target died")
		return
	end

	local distance = (myRoot.Position - targetRoot.Position).Magnitude
	if distance > BREAK_RANGE then
		unlockTarget("target out of range")
		return
	end

	-- Rotate character to face target without forcing CFrame
	-- Use humanoid auto-rotate by setting a look vector instead
	local flatDir = Vector3.new(
		targetRoot.Position.X - myRoot.Position.X,
		0,
		targetRoot.Position.Z - myRoot.Position.Z
	)
	if flatDir.Magnitude > 0.1 then
		local targetCFrame = CFrame.new(myRoot.Position, myRoot.Position + flatDir)
		myRoot.CFrame = myRoot.CFrame:Lerp(targetCFrame, 0.15)
	end

	-- Update camera
	local camera = Workspace.CurrentCamera
	if not camera then return end

	local targetBasePos = targetRoot.Position + Vector3.new(0, 2.5, 0)
	local toTarget = Vector3.new(
		targetBasePos.X - myRoot.Position.X,
		0,
		targetBasePos.Z - myRoot.Position.Z
	)

	if toTarget.Magnitude <= 0.001 then return end

	local yawDirection = toTarget.Unit
	local yawCFrame = CFrame.lookAt(Vector3.zero, yawDirection)
	local pitchCFrame = CFrame.Angles(pitchAngle, 0, 0)
	local finalCameraCFrame = CFrame.new(targetBasePos) * yawCFrame * pitchCFrame * CFrame.new(CAMERA_OFFSET)

	camera.CFrame = finalCameraCFrame
end

local function lockOntoTarget(targetPlayer)
	if not targetPlayer then return end

	local camera = Workspace.CurrentCamera
	if not camera then return end

	local myRoot = getCharacterParts(LOCAL_PLAYER)
	local targetRoot, targetHumanoid = getCharacterParts(targetPlayer)
	if not myRoot or not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
		return
	end

	savedCameraType = camera.CameraType
	savedCameraSubject = camera.CameraSubject

	camera.CameraType = Enum.CameraType.Scriptable
	isLocked = true
	lockedPlayer = targetPlayer
	pitchAngle = 0

	createIndicatorForTarget(targetPlayer.Character)

	local targetBasePos = targetRoot.Position + Vector3.new(0, 2.5, 0)
	local lockStartCFrame = CFrame.new(targetBasePos + CAMERA_OFFSET, targetBasePos)
	tweenCameraTo(lockStartCFrame, 0.2)

	disconnectConnection(heartbeatConnection)
	heartbeatConnection = RunService.Heartbeat:Connect(updateLockStep)

	disconnectConnection(deathConnection)
	deathConnection = targetHumanoid.Died:Connect(function()
		unlockTarget("target humanoid died signal")
	end)

	debugPrint("Locked target:", targetPlayer.Name)
end

local function toggleTargetLock()
	if isLocked then
		unlockTarget("manual toggle")
		return
	end

	local target = findNearestTarget(SEARCH_RANGE)
	if not target then
		debugPrint("No target found within", SEARCH_RANGE, "studs")
		return
	end

	lockOntoTarget(target)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == LOCK_KEY then
		toggleTargetLock()
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if not isLocked or gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		pitchAngle = math.clamp(
			pitchAngle - input.Delta.Y * PITCH_SENSITIVITY,
			MIN_PITCH,
			MAX_PITCH
		)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if isLocked and player == lockedPlayer then
		unlockTarget("target player left")
	end
end)

LOCAL_PLAYER.CharacterAdded:Connect(function()
	if isLocked then unlockTarget("local respawn") end
end)

LOCAL_PLAYER.CharacterRemoving:Connect(function()
	if isLocked then unlockTarget("local character removing") end
end)

debugPrint("TargetLockController initialized")