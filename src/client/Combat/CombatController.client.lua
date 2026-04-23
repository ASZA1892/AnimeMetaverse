-- src/client/Combat/CombatController.client.lua

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatRemote = ReplicatedStorage:WaitForChild("CombatRemote", 10)
if not CombatRemote then error("CombatRemote not found") end

local CombatActions = require(ReplicatedStorage.Shared.Types.CombatActions)
local Constants = require(ReplicatedStorage.Shared.Types.constants)
local MoveDefinitions = require(ReplicatedStorage.Shared.Types.MoveDefinitions)

local CameraShaker = nil
do
	local ok, mod = pcall(require, script.Parent.CameraShaker)
	if ok and mod then
		CameraShaker = mod
	else
		warn("CombatController: CameraShaker not found")
	end
end

local player = Players.LocalPlayer

local function isKeyDown(keyCode)
	return UserInputService:IsKeyDown(keyCode)
end

local function isAirborne()
	local char = player.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return false end
	local state = hum:GetState()
	return state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
end

local function buildInputTable()
	return {
		M1 = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1),
		M2 = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2),
		E  = isKeyDown(Enum.KeyCode.E),
		W  = isKeyDown(Enum.KeyCode.W),
		A  = isKeyDown(Enum.KeyCode.A) or isKeyDown(Enum.KeyCode.D),
		S  = isKeyDown(Enum.KeyCode.S),
		Crouch = isKeyDown(Enum.KeyCode.LeftControl) or isKeyDown(Enum.KeyCode.C),
		Sprint = isKeyDown(Enum.KeyCode.LeftShift),
		Q  = isKeyDown(Enum.KeyCode.Q),
		Space = isAirborne(),
	}
end

local function buildContext()
	local char = player.Character
	local isClose = false
	if char and char.PrimaryPart then
		local root = char.PrimaryPart
		for _, other in ipairs(Workspace:GetChildren()) do
			if other:IsA("Model") and other ~= char then
				local hum = other:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					local otherRoot = other.PrimaryPart or other:FindFirstChild("HumanoidRootPart")
					if otherRoot and (root.Position - otherRoot.Position).Magnitude <= 4 then
						isClose = true
						break
					end
				end
			end
		end
	end
	return {
		isClose = isClose,
		isAirborne = isAirborne(),
		isSprinting = isKeyDown(Enum.KeyCode.LeftShift) and (char and char.Humanoid and char.Humanoid.MoveDirection.Magnitude > 0),
		isDashing = false,
	}
end

local function findMoveForCurrentInput()
	local inputTable = buildInputTable()
	local context = buildContext()
	local move = MoveDefinitions.FindMoveByInput(inputTable, context)
	return move and move.id or nil
end

local function shake(intensity, duration)
	if CameraShaker then
		CameraShaker.Shake(intensity, duration)
	end
end

local function fireAttack()
	local moveId = findMoveForCurrentInput()
	if not moveId then
		print("[Client] No move matched current input")
		return
	end

	-- Animations disabled until custom Moon Animator anims are ready
	-- if AnimationLoader then AnimationLoader.playAttackAnimation(moveId) end

	local mouse = player:GetMouse()
	local aimPosition = mouse.Hit.Position

	print("[Client] Firing move:", moveId)
	CombatRemote:FireServer(CombatActions.ClientToServer.M1_ATTACK, {
		clientSentAt = tick(),
		moveId = moveId,
		aimPosition = aimPosition,
	})
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	local key = input.KeyCode
	local userInput = input.UserInputType

	if key == Enum.KeyCode.F then
		CombatRemote:FireServer(CombatActions.ClientToServer.BLOCK_START)
		CombatRemote:FireServer(CombatActions.ClientToServer.PARRY)
		return
	elseif key == Enum.KeyCode.G then
		CombatRemote:FireServer(CombatActions.ClientToServer.GRAB_ATTEMPT)
		return
	end

	if userInput == Enum.UserInputType.MouseButton1 then
		fireAttack()
	elseif userInput == Enum.UserInputType.MouseButton2 then
		fireAttack()
	elseif key == Enum.KeyCode.E then
		fireAttack()
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.F then
		CombatRemote:FireServer(CombatActions.ClientToServer.BLOCK_END)
	end
	if input.KeyCode == Enum.KeyCode.G then
		CombatRemote:FireServer(CombatActions.ClientToServer.GRAB_RELEASE)
	end
end)

CombatRemote.OnClientEvent:Connect(function(action, data)

	if action == CombatActions.ServerToClient.HIT_CONFIRMED then
		if data.attacker == player then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local originalSpeed = humanoid.WalkSpeed
				humanoid.WalkSpeed = 0
				task.delay(data.hitStop or Constants.HIT_STOP_DURATION, function()
					if humanoid and humanoid.Parent then
						humanoid.WalkSpeed = originalSpeed
					end
				end)
			end
			shake(0.4, 0.15)
		end

	elseif action == CombatActions.ServerToClient.KNOCKBACK then
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and data and data.velocity then
			root.AssemblyLinearVelocity = data.velocity
			shake(0.5, 0.15)
		end

	elseif action == CombatActions.ServerToClient.PARRY_SUCCESS then
		if data.parrier == player then
			print("✅ You parried " .. data.attacker.Name .. "!")
			shake(0.6, 0.2)
		elseif data.attacker == player then
			print("❌ You got parried by " .. data.parrier.Name .. "!")
			shake(0.8, 0.25)
		end

	elseif action == CombatActions.ServerToClient.GUARD_BROKEN then
		if data.player == player then
			print("💔 Guard broken!")
			shake(1.0, 0.3)
		end

	elseif action == CombatActions.ServerToClient.GRAPPLE_CONFIRMED then
		print("✅ Grapple confirmed! Grabbed: " .. tostring(data.targetName))
		shake(0.3, 0.12)

	elseif action == CombatActions.ServerToClient.GRAPPLE_CAUGHT then
		print("⚠️ You were grabbed by: " .. tostring(data.attackerName))
		shake(0.7, 0.2)

	elseif action == CombatActions.ServerToClient.GRAPPLE_RELEASED then
		print("🔓 Grapple released")

	end
end)

print("✅ CombatController client initialized (with Guard/Parry/Grapple)")