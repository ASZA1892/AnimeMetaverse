-- src/server/Combat/GuardSystem.server.lua
-- Server-side guard bar and parry logic (fully hardened)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Robust requires (prevents nil errors)
local sharedFolder = ReplicatedStorage:WaitForChild("Shared", 5)
local typesFolder = sharedFolder:WaitForChild("Types", 5)

local Constants = require(typesFolder:WaitForChild("constants"))
local CombatActions = require(typesFolder:WaitForChild("CombatActions"))
local CombatStateMachine = require(script.Parent:WaitForChild("CombatStateMachine"))

local CombatRemote = ReplicatedStorage:WaitForChild("CombatRemote")

local GuardSystem = {}

-- Weak-key tables to prevent memory leaks
local playerGuard = setmetatable({}, { __mode = "k" })
local playerParryTimestamps = setmetatable({}, { __mode = "k" })
local playerLastBlockTime = setmetatable({}, { __mode = "k" })
local playerGuardDirty = setmetatable({}, { __mode = "k" })

local PARRY_COOLDOWN = Constants.PARRY_COOLDOWN or 1.0

-- Helper: resolve a target (Player or Model) to a Player instance (or nil for NPCs)
local function resolvePlayerFromTarget(target)
	if not target then return nil end
	if typeof(target) == "Instance" and target:IsA("Model") then
		return Players:GetPlayerFromCharacter(target)
	elseif typeof(target) == "Instance" and target:IsA("Player") then
		return target
	end
	return nil
end

-- Initialize per-player data (only call with a Player instance)
local function initPlayer(player)
	if not player then return end
	if not playerGuard[player] then
		playerGuard[player] = Constants.MAX_GUARD
		playerGuardDirty[player] = true
	end
end

function GuardSystem.GetGuard(player)
	initPlayer(player)
	return playerGuard[player] or Constants.MAX_GUARD
end

function GuardSystem.SetGuard(player, value)
	if not player then return end
	initPlayer(player)
	local old = playerGuard[player]
	playerGuard[player] = math.clamp(value, 0, Constants.MAX_GUARD)
	if playerGuard[player] ~= old then
		playerGuardDirty[player] = true
	end
end

function GuardSystem.UpdateGuard(player, deltaTime)
	if not player then return end
	initPlayer(player)
	local now = tick()
	local lastBlock = playerLastBlockTime[player] or 0
	
	if CombatStateMachine.GetState(player) ~= CombatStateMachine.States.Blocking then
		if now - lastBlock >= Constants.GUARD_REGEN_DELAY then
			local newGuard = math.min(playerGuard[player] + Constants.GUARD_REGEN_RATE * deltaTime, Constants.MAX_GUARD)
			if newGuard ~= playerGuard[player] then
				playerGuard[player] = newGuard
				playerGuardDirty[player] = true
			end
		end
	end
end

function GuardSystem.StartBlocking(player)
	initPlayer(player)
	CombatStateMachine.TrySetState(player, CombatStateMachine.States.Blocking)
end

function GuardSystem.StopBlocking(player)
	if not player then return end
	playerLastBlockTime[player] = tick()
	if CombatStateMachine.GetState(player) == CombatStateMachine.States.Blocking then
		CombatStateMachine.TrySetState(player, CombatStateMachine.States.Idle)
	end
end

function GuardSystem.ProcessHit(attacker, target, baseDamage, moveData)
	local now = tick()
	local targetPlayer = resolvePlayerFromTarget(target)
	local attackerPlayer = resolvePlayerFromTarget(attacker)
	initPlayer(targetPlayer)
	
	-- Parry check (players only)
	if targetPlayer then
		local parryTime = playerParryTimestamps[targetPlayer]
		if parryTime and (now - parryTime) <= Constants.PARRY_WINDOW then
			playerParryTimestamps[targetPlayer] = nil
			
			-- Stun attacker (only if attacker is a Player)
			if attackerPlayer then
				CombatStateMachine.ForceState(attackerPlayer, CombatStateMachine.States.Stunned, {
					expiresAt = now + Constants.PARRY_STUN_DURATION
				})
			end
			
			-- Notify involved players
			CombatRemote:FireClient(targetPlayer, CombatActions.ServerToClient.PARRY_SUCCESS, {
				attacker = attackerPlayer,
				parrier = targetPlayer,
			})
			if attackerPlayer and attackerPlayer ~= targetPlayer then
				CombatRemote:FireClient(attackerPlayer, CombatActions.ServerToClient.PARRY_SUCCESS, {
					attacker = attackerPlayer,
					parrier = targetPlayer
				})
			end
			
			return 0, true, false
		end
	end
	
	-- Blocking logic (players only)
	local isBlocking = targetPlayer and (CombatStateMachine.GetState(targetPlayer) == CombatStateMachine.States.Blocking)
	if isBlocking and targetPlayer then
		local currentGuard = playerGuard[targetPlayer] or Constants.MAX_GUARD
		local newGuard = math.max(0, currentGuard - Constants.GUARD_DEPLETION_PER_HIT)
		GuardSystem.SetGuard(targetPlayer, newGuard)
		
		local chipDamage = baseDamage * Constants.CHIP_DAMAGE_PERCENT
		
		if newGuard <= 0 then
			CombatStateMachine.ForceState(targetPlayer, CombatStateMachine.States.Stunned, {
				expiresAt = now + Constants.GUARD_BREAK_STUN
			})
			
			CombatRemote:FireClient(targetPlayer, CombatActions.ServerToClient.GUARD_BROKEN, {
				player = targetPlayer
			})
			
			GuardSystem.SetGuard(targetPlayer, Constants.MAX_GUARD)
			return chipDamage, false, true
		end
		
		playerLastBlockTime[targetPlayer] = now
		return chipDamage, false, false
	end
	
	return baseDamage, false, false
end

function GuardSystem.RecordParry(player)
	if not player then return false end
	initPlayer(player)
	local now = tick()
	local last = playerParryTimestamps[player]
	if last and (now - last) < PARRY_COOLDOWN then
		return false
	end
	playerParryTimestamps[player] = now
	return true
end

-- Initialize players when they join
Players.PlayerAdded:Connect(function(player)
	initPlayer(player)
end)

-- Cleanup when player leaves
Players.PlayerRemoving:Connect(function(player)
	playerGuard[player] = nil
	playerParryTimestamps[player] = nil
	playerLastBlockTime[player] = nil
	playerGuardDirty[player] = nil
end)

-- Heartbeat for guard regen and sending updates
task.spawn(function()
	local lastTick = tick()
	while true do
		local now = tick()
		local deltaTime = now - lastTick
		lastTick = now
		
		for _, player in ipairs(Players:GetPlayers()) do
			GuardSystem.UpdateGuard(player, deltaTime)
			
			if playerGuardDirty[player] then
				CombatRemote:FireClient(player, CombatActions.ServerToClient.GUARD_UPDATE, {
					player = player,
					guard = playerGuard[player],
					max = Constants.MAX_GUARD
				})
				playerGuardDirty[player] = false
			end
		end
		
		task.wait(0.15)
	end
end)

return GuardSystem