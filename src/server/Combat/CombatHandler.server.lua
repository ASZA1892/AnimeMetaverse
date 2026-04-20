-- src/server/Combat/CombatHandler.server.lua
-- Data-driven server-side combat handler with Guard/Parry (hardened)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Remote event (safe find/create)
local CombatRemote = ReplicatedStorage:FindFirstChild("CombatRemote")
if not CombatRemote then
	CombatRemote = Instance.new("RemoteEvent")
	CombatRemote.Name = "CombatRemote"
	CombatRemote.Parent = ReplicatedStorage
end

-- Modules
local CombatActions = require(ReplicatedStorage.Shared.Types.CombatActions)
local Constants = require(ReplicatedStorage.Shared.Types.constants)
local CombatStateMachine = require(script.Parent.CombatStateMachine)
local MoveDefinitions = require(ReplicatedStorage.Shared.Types.MoveDefinitions)
local GuardSystem = require(script.Parent.GuardSystem)

-- Helper: find the character model from any descendant part
local function findCharacterModelFromPart(part)
	local node = part
	local depth = 0
	while node and depth < 12 do
		if node:IsA("Model") then
			if node:FindFirstChildOfClass("Humanoid") or node:FindFirstChild("HumanoidRootPart") then
				return node
			end
		end
		node = node.Parent
		depth = depth + 1
	end
	return nil
end

-- Helper: get humanoid from player
local function getHumanoidFromPlayer(player)
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

-- Helper: check if player is alive
local function isPlayerAlive(player)
	local hum = getHumanoidFromPlayer(player)
	return hum and hum.Health > 0
end

-- Apply move-specific effects (works with both Player and Model)
local function applyEffects(targetModel, move, attacker)
	local hum = targetModel:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	
	if move.slow then
		local originalSpeed = hum.WalkSpeed
		hum.WalkSpeed = originalSpeed * move.slow.percent
		task.delay(move.slow.duration, function()
			if hum and hum.Parent then
				hum.WalkSpeed = originalSpeed
			end
		end)
	end
	
	if move.launch then
		local root = targetModel.PrimaryPart or targetModel:FindFirstChild("HumanoidRootPart")
		if root then
			root.Velocity = Vector3.new(0, move.launchPower or 25, 0)
		end
	end
	
	if move.stun and move.stun > 0 then
		local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
		if targetPlayer then
			CombatStateMachine.ForceState(targetPlayer, CombatStateMachine.States.Stunned, {
				expiresAt = tick() + move.stun
			})
		else
			if hum then
				local oldWalkSpeed = hum.WalkSpeed
				hum.WalkSpeed = 0
				task.delay(move.stun, function()
					if hum and hum.Parent then
						hum.WalkSpeed = oldWalkSpeed
					end
				end)
			end
		end
	end
	
	if move.groundBounce then
		local root = targetModel.PrimaryPart or targetModel:FindFirstChild("HumanoidRootPart")
		if root then
			root.Velocity = Vector3.new(0, 20, 0)
		end
	end
end

-- Main remote listener
CombatRemote.OnServerEvent:Connect(function(player: Player, action: string, data: any)
	local currentState = CombatStateMachine.GetState(player)
	
	-- Block handling
	if action == CombatActions.ClientToServer.BLOCK_START then
		GuardSystem.StartBlocking(player)
		return
	elseif action == CombatActions.ClientToServer.BLOCK_END then
		GuardSystem.StopBlocking(player)
		return
	end
	
	-- Parry attempt
	if action == CombatActions.ClientToServer.PARRY then
		local success = GuardSystem.RecordParry(player)
		if not success and Constants.DEBUG then
			print("  ↳ Parry on cooldown for " .. player.Name)
		end
		return
	end
	
	-- Attack handling
	local moveId = data and data.moveId
	if not moveId then return end
	
	local move = MoveDefinitions.GetMove(moveId)
	if not move then
		if Constants.DEBUG then print("  ↳ Unknown move: " .. tostring(moveId)) end
		return
	end
	
	if Constants.DEBUG then
		print("[Combat] " .. player.Name .. " | Move: " .. moveId .. " | State: " .. currentState)
	end
	
	-- Validate attack permission
	if not CombatStateMachine.CanAttack(player) then
		if Constants.DEBUG then print("  ↳ Rejected: Cannot attack from state " .. currentState) end
		return
	end
	
	-- Move-specific validations
	if move.requiresDash and currentState ~= CombatStateMachine.States.Dashing then
		if Constants.DEBUG then print("  ↳ Rejected: Move requires dash") end
		return
	end
	if move.requiresAirborne and not CombatStateMachine.GetIsAirborne(player) then
		if Constants.DEBUG then print("  ↳ Rejected: Move requires airborne") end
		return
	end
	
	-- Transition to Attacking state
	local success, reason = CombatStateMachine.TrySetState(player, CombatStateMachine.States.Attacking, {
		expiresAt = tick() + move.cooldown
	})
	if not success then
		if Constants.DEBUG then print("  ↳ Rejected: State transition failed: " .. tostring(reason)) end
		return
	end
	
	local character = player.Character
	if not character or not character.PrimaryPart then
		if Constants.DEBUG then print("  ↳ Rejected: No character") end
		CombatStateMachine.ForceState(player, CombatStateMachine.States.Idle)
		return
	end
	
	local rootPart = character.PrimaryPart
	
	-- Calculate hitbox position
	local forward = rootPart.CFrame.LookVector
	local offset = forward * (move.range / 2)
	local center = rootPart.Position + offset
	local boxCFrame = CFrame.new(center)
	
	-- Overlap detection
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {character}
	
	local partsInBox = Workspace:GetPartBoundsInBox(boxCFrame, move.hitboxSize, overlapParams)
	
	-- Find first valid target (player or NPC)
	local hitModel = nil
	local hitPlayer = nil
	for _, part in ipairs(partsInBox) do
		local model = findCharacterModelFromPart(part)
		if model and model ~= character then
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				hitModel = model
				hitPlayer = Players:GetPlayerFromCharacter(model)
				break
			end
		end
	end
	
	if hitModel then
		local hitHumanoid = hitModel:FindFirstChildOfClass("Humanoid")
		local targetName = hitPlayer and hitPlayer.Name or hitModel.Name
		
		-- Canonical attacker/target players
		local attackerPlayer = player
		local targetPlayer = hitPlayer  -- nil for NPCs
		
		-- Process through guard system
		local finalDamage, wasParried, guardBroken = GuardSystem.ProcessHit(attackerPlayer, targetPlayer or hitModel, move.damage, move)
		
		if wasParried then
			if Constants.DEBUG then print("  ↳ Parried by " .. targetName) end
			return
		end
		
		if finalDamage > 0 then
			hitHumanoid:TakeDamage(finalDamage)
			if Constants.DEBUG then print("  ↳ Hit! " .. targetName .. " took " .. finalDamage .. " damage from " .. moveId) end
		else
			if Constants.DEBUG then print("  ↳ Blocked! " .. targetName) end
		end
		
		-- Knockback and effects (only if not parried)
		if not wasParried then
			if move.knockback > 0 then
				local hitRoot = hitModel.PrimaryPart or hitModel:FindFirstChild("HumanoidRootPart")
				if hitRoot then
					local knockbackDir = (hitRoot.Position - rootPart.Position).Unit
					local isTargetBlocking = targetPlayer and (CombatStateMachine.GetState(targetPlayer) == CombatStateMachine.States.Blocking)
					local multiplier = isTargetBlocking and 0.5 or 1.0
					hitRoot.Velocity = knockbackDir * move.knockback * 10 * multiplier
				end
			end
			
			local isTargetBlocking = targetPlayer and (CombatStateMachine.GetState(targetPlayer) == CombatStateMachine.States.Blocking)
			if not isTargetBlocking then
				applyEffects(hitModel, move, attackerPlayer)
			end
		end
		
		-- Lunge (attacker)
		if move.lunge then
			rootPart.Velocity = forward * move.lunge * 20
		end
		
		-- Fire HitConfirmed to involved clients only
		if finalDamage > 0 or guardBroken then
			local hitData = {
				attacker = attackerPlayer,
				target = targetPlayer,
				position = hitModel.PrimaryPart and hitModel.PrimaryPart.Position or Vector3.zero,
				damage = finalDamage,
				moveId = moveId,
				hitStop = Constants.HIT_STOP_DURATION,
				serverTimestamp = tick(),
				blocked = (targetPlayer and (CombatStateMachine.GetState(targetPlayer) == CombatStateMachine.States.Blocking)) or false,
				guardBroken = guardBroken
			}
			
			-- Notify attacker
			if attackerPlayer then
				CombatRemote:FireClient(attackerPlayer, CombatActions.ServerToClient.HIT_CONFIRMED, hitData)
			end
			-- Notify target
			if targetPlayer then
				CombatRemote:FireClient(targetPlayer, CombatActions.ServerToClient.HIT_CONFIRMED, hitData)
			end
		end
	else
		if Constants.DEBUG then print("  ↳ Miss (" .. moveId .. ")") end
	end
end)

print("✅ CombatHandler server initialized (hardened)")