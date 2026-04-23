-- src/client/Combat/TiltController.client.lua

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatRemote = ReplicatedStorage:WaitForChild("CombatRemote", 10)
if not CombatRemote then
	error("TiltController: CombatRemote not found")
end

local CombatActions = require(ReplicatedStorage.Shared.Types.CombatActions)
local Constants = require(ReplicatedStorage.Shared.Types.constants)

local LOCAL_PLAYER = Players.LocalPlayer

local LERP_ALPHA = 0.12
local RETURN_ALPHA = 0.08
local ATTACK_TILT_DURATION = 0.14

local MAX_ROLL = math.rad(12)
local MAX_PITCH_FORWARD = math.rad(6)
local MAX_PITCH_BACKWARD = math.rad(4)
local MAX_ATTACK_PITCH = math.rad(4)

local character = nil
local rootPart = nil
local motor6D = nil -- We tilt via Motor6D on the root joint instead of raw CFrame

local isDashing = false
local dashEndsAt = 0
local attackEndsAt = 0
local currentPitch = 0
local currentRoll = 0

local heartbeatConn = nil
local charAddedConn = nil
local charRemovingConn = nil
local remoteConn = nil

local function dbg(...)
	if Constants.DEBUG then
		print("[TiltController]", ...)
	end
end

local function disconnect(c)
	if c then c:Disconnect() end
end

local function bindCharacter(char)
	character = char
	rootPart = char and char:FindFirstChild("HumanoidRootPart") or nil
	-- Find the root joint Motor6D for tilt
	if rootPart then
		local lowerTorso = char:FindFirstChild("LowerTorso")
		if lowerTorso then
			motor6D = lowerTorso:FindFirstChild("Root")
		end
	end
	currentPitch = 0
	currentRoll = 0
	isDashing = false
	attackEndsAt = 0
	dashEndsAt = 0
end

local function getTargetAngles()
	local now = tick()
	local targetPitch = 0
	local targetRoll = 0

	if isDashing and now < dashEndsAt then
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			targetRoll = -MAX_ROLL
		elseif UserInputService:IsKeyDown(Enum.KeyCode.D) then
			targetRoll = MAX_ROLL
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			targetPitch = -MAX_PITCH_FORWARD
		elseif UserInputService:IsKeyDown(Enum.KeyCode.S) then
			targetPitch = MAX_PITCH_BACKWARD
		end
	end

	if now < attackEndsAt then
		targetPitch = targetPitch + (-MAX_ATTACK_PITCH)
	end

	return targetPitch, targetRoll
end

local function onHeartbeat()
	if not motor6D or not motor6D.Parent then return end

	local now = tick()
	if isDashing and now >= dashEndsAt then
		isDashing = false
	end

	local targetPitch, targetRoll = getTargetAngles()
	local alpha = (targetPitch == 0 and targetRoll == 0) and RETURN_ALPHA or LERP_ALPHA

	currentPitch = currentPitch + (targetPitch - currentPitch) * alpha
	currentRoll = currentRoll + (targetRoll - currentRoll) * alpha

	-- Apply tilt via Motor6D transform — this doesn't fight physics
	motor6D.Transform = CFrame.Angles(currentPitch, 0, currentRoll)
end

local function startHeartbeat()
	disconnect(heartbeatConn)
	heartbeatConn = RunService.Heartbeat:Connect(onHeartbeat)
end

local function stopHeartbeat()
	disconnect(heartbeatConn)
	heartbeatConn = nil
	if motor6D then
		motor6D.Transform = CFrame.identity
	end
	currentPitch = 0
	currentRoll = 0
end

LOCAL_PLAYER.CharacterAdded:Connect(function(char)
	bindCharacter(char)
	startHeartbeat()
	dbg("Character bound")
end)

LOCAL_PLAYER.CharacterRemoving:Connect(function()
	stopHeartbeat()
	character = nil
	rootPart = nil
	motor6D = nil
	dbg("Character removed")
end)

remoteConn = CombatRemote.OnClientEvent:Connect(function(action, data)
	if action == CombatActions.ServerToClient.DASH_CONFIRMED then
		isDashing = true
		dashEndsAt = tick() + ((data and data.duration) or 0.2)
		dbg("Dash tilt triggered")
	elseif action == CombatActions.ServerToClient.HIT_CONFIRMED then
		if data and data.attacker == LOCAL_PLAYER then
			attackEndsAt = tick() + ATTACK_TILT_DURATION
			dbg("Attack tilt triggered")
		end
	end
end)

-- Bind existing character if already spawned
if LOCAL_PLAYER.Character then
	bindCharacter(LOCAL_PLAYER.Character)
	startHeartbeat()
end

dbg("TiltController initialized")