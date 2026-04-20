-- src/client/Combat/CombatController.client.lua
-- Robust input detection for all strikes and kicks (context‑aware matcher)
-- With Guard/Parry support

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CombatRemote = ReplicatedStorage:WaitForChild("CombatRemote", 10)
if not CombatRemote then error("CombatRemote not found") end

local CombatActions = require(ReplicatedStorage.Shared.Types.CombatActions)
local Constants = require(ReplicatedStorage.Shared.Types.constants)
local MoveDefinitions = require(ReplicatedStorage.Shared.Types.MoveDefinitions)

local player = Players.LocalPlayer

-- Helper: check if a key is physically held down
local function isKeyDown(keyCode)
	return UserInputService:IsKeyDown(keyCode)
end

-- Helper: check if player is airborne
local function isAirborne()
	local char = player.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return false end
	local state = hum:GetState()
	return state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
end

-- Helper: build input table from current key states
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

-- Helper: build context table (client-side approximation)
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

-- Helper: find move using the context‑aware matcher
local function findMoveForCurrentInput()
	local inputTable = buildInputTable()
	local context = buildContext()
	local move = MoveDefinitions.FindMoveByInput(inputTable, context)
	return move and move.id or nil
end

-- Fire attack to server
local function fireAttack()
	local moveId = findMoveForCurrentInput()
	if moveId then
		print("[Client] Firing move:", moveId)
		CombatRemote:FireServer(CombatActions.ClientToServer.M1_ATTACK, {
			clientSentAt = tick(),
			moveId = moveId,
		})
	else
		print("[Client] No move matched current input")
	end
end

-- Input began (block/parry, grab, attacks)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	local key = input.KeyCode
	local userInput = input.UserInputType
	
	-- Block + Parry (F key)
	if key == Enum.KeyCode.F then
		CombatRemote:FireServer(CombatActions.ClientToServer.BLOCK_START)
		CombatRemote:FireServer(CombatActions.ClientToServer.PARRY)
		return
	elseif key == Enum.KeyCode.G then
		CombatRemote:FireServer(CombatActions.ClientToServer.GRAB_ATTEMPT)
		return
	end
	
	-- Attack triggers
	if userInput == Enum.UserInputType.MouseButton1 then
		fireAttack()
	elseif userInput == Enum.UserInputType.MouseButton2 then
		fireAttack()
	elseif key == Enum.KeyCode.E then
		fireAttack()
	end
end)

-- Input ended (block release)
UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.F then
		CombatRemote:FireServer(CombatActions.ClientToServer.BLOCK_END)
	end
end)

-- Handle server events
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
			
			local camera = Workspace.CurrentCamera
			if camera then
				local originalCFrame = camera.CFrame
				local joltOffset = CFrame.new(0, Constants.CAMERA_JOLT_STRENGTH, Constants.CAMERA_JOLT_STRENGTH * 2)
				local tweenInfo = TweenInfo.new(
					Constants.CAMERA_JOLT_DURATION,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				)
				local tween = TweenService:Create(camera, tweenInfo, {CFrame = originalCFrame * joltOffset})
				tween:Play()
				tween.Completed:Connect(function()
					if camera then
						camera.CFrame = originalCFrame
					end
				end)
			end
		end
		
	elseif action == CombatActions.ServerToClient.PARRY_SUCCESS then
		if data.parrier == player then
			print("✅ You parried " .. data.attacker.Name .. "!")
			-- TODO: Add screen flash / sound effect
		elseif data.attacker == player then
			print("❌ You got parried by " .. data.parrier.Name .. "!")
		end
		
	elseif action == CombatActions.ServerToClient.GUARD_BROKEN then
		if data.player == player then
			print("💔 Guard broken!")
			-- TODO: Add screen shake / sound effect
		end
	end
end)

print("✅ CombatController client initialized (with Guard/Parry)")