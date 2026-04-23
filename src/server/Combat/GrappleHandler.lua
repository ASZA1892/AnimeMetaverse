local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Types.constants)
local CombatActions = require(ReplicatedStorage.Shared.Types.CombatActions)

local GrappleHandler = {}

local GRAPPLE_COOLDOWN = Constants.GRAPPLE_COOLDOWN or 6
local GRAPPLE_RANGE = Constants.GRAPPLE_RANGE or 5
local GRAPPLE_DISABLE_DURATION = Constants.GRAPPLE_DISABLE_DURATION or 1.5
local GRAPPLE_THROW_DISTANCE = Constants.GRAPPLE_THROW_DISTANCE or 15

local lastGrappleAt = setmetatable({}, { __mode = "k" })
local activeByAttacker = setmetatable({}, { __mode = "k" })
local activeByTarget = setmetatable({}, { __mode = "k" })

local function dbg(...)
	if Constants.DEBUG then
		print("[GrappleHandler]", ...)
	end
end

local function getRoot(character)
	if not character then return nil end
	return character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
end

local function setCombatState(CombatStateMachine, player, stateName, meta)
	if not CombatStateMachine or not CombatStateMachine.ForceState or not player then
		return false
	end
	CombatStateMachine.ForceState(player, stateName, meta)
	return true
end

local function setDisabledState(CombatStateMachine, player, expiresAt)
	CombatStateMachine.ForceState(player, "Disabled", { expiresAt = expiresAt })
end

local function clearPair(attacker, target)
	local pair = activeByAttacker[attacker]
	if pair and pair.target == target then
		activeByAttacker[attacker] = nil
	end
	local reverse = activeByTarget[target]
	if reverse and reverse.attacker == attacker then
		activeByTarget[target] = nil
	end
end

local function releasePair(attacker, target, CombatStateMachine, token)
	local pair = activeByAttacker[attacker]
	if not pair or pair.target ~= target then return end
	if token and pair.token ~= token then return end

	clearPair(attacker, target)
	setCombatState(CombatStateMachine, attacker, "Idle")
	setCombatState(CombatStateMachine, target, "Idle")
end

local function findNearestTarget(attacker)
	local attackerCharacter = attacker.Character
	local attackerRoot = getRoot(attackerCharacter)
	if not attackerRoot then return nil end

	local nearestPlayer = nil
	local nearestDistance = math.huge

	for _, candidate in ipairs(Players:GetPlayers()) do
		if candidate ~= attacker then
			local candidateCharacter = candidate.Character
			local candidateRoot = getRoot(candidateCharacter)
			if candidateRoot and candidateCharacter and candidateCharacter:IsDescendantOf(Workspace) then
				local distance = (candidateRoot.Position - attackerRoot.Position).Magnitude
				dbg("Checking", candidate.Name, "distance:", distance, "range:", GRAPPLE_RANGE)
				if distance <= GRAPPLE_RANGE and distance < nearestDistance then
					nearestDistance = distance
					nearestPlayer = candidate
				end
			end
		end
	end

	return nearestPlayer
end

function GrappleHandler.ProcessGrapple(player, data, CombatStateMachine, CombatRemote)
	local _ = data
	if not player or not CombatStateMachine or not CombatRemote then return end

	local state = CombatStateMachine.GetState(player)
	if state ~= "Idle" and state ~= "Attacking" then
		dbg(player.Name, "grapple denied: invalid state", state)
		return
	end

	local now = tick()
	local last = lastGrappleAt[player] or 0
	if now - last < GRAPPLE_COOLDOWN then
		dbg(player.Name, "grapple denied: cooldown")
		return
	end

	if activeByAttacker[player] then
		dbg(player.Name, "grapple denied: already grappling")
		return
	end

	local target = findNearestTarget(player)
	if not target then
		dbg(player.Name, "grapple missed: no target in range")
		return
	end
	if activeByTarget[target] then
		dbg(player.Name, "grapple denied: target already grappled")
		return
	end

	lastGrappleAt[player] = now

	local expiresAt = now + GRAPPLE_DISABLE_DURATION
	setCombatState(CombatStateMachine, player, "Grappling", {
		expiresAt = expiresAt,
		targetUserId = target.UserId
	})
	setDisabledState(CombatStateMachine, target, expiresAt)

	local token = tostring(now) .. "_" .. tostring(player.UserId) .. "_" .. tostring(target.UserId)
	activeByAttacker[player] = {
		target = target,
		startedAt = now,
		expiresAt = expiresAt,
		token = token,
	}
	activeByTarget[target] = {
		attacker = player,
		token = token,
	}

	dbg(player.Name, "grapple confirmed on", target.Name)

	CombatRemote:FireClient(player, CombatActions.ServerToClient.GRAPPLE_CONFIRMED, {
		target = target,
		targetUserId = target.UserId,
		targetName = target.Name,
		duration = GRAPPLE_DISABLE_DURATION,
	})
	CombatRemote:FireClient(target, CombatActions.ServerToClient.GRAPPLE_CAUGHT, {
		attacker = player,
		attackerUserId = player.UserId,
		attackerName = player.Name,
		duration = GRAPPLE_DISABLE_DURATION,
	})

	task.delay(GRAPPLE_DISABLE_DURATION, function()
		releasePair(player, target, CombatStateMachine, token)
	end)
end

function GrappleHandler.ProcessGrappleRelease(player, data, CombatStateMachine, CombatRemote)
	local _ = data
	local _2 = CombatRemote
	if not player or not CombatStateMachine then return end

	local pair = activeByAttacker[player]
	if not pair then
		dbg(player.Name, "release: no active grapple")
		return
	end

	local target = pair.target
	if not target then
		activeByAttacker[player] = nil
		return
	end

	local attackerRoot = getRoot(player.Character)
	local targetRoot = getRoot(target.Character)
	if attackerRoot and targetRoot then
		targetRoot.AssemblyLinearVelocity = attackerRoot.CFrame.LookVector * (GRAPPLE_THROW_DISTANCE * 10)
		dbg(player.Name, "threw", target.Name)
	end

	releasePair(player, target, CombatStateMachine, pair.token)
end

Players.PlayerRemoving:Connect(function(player)
	lastGrappleAt[player] = nil

	local pair = activeByAttacker[player]
	if pair and pair.target then
		activeByTarget[pair.target] = nil
	end
	activeByAttacker[player] = nil

	local reverse = activeByTarget[player]
	if reverse and reverse.attacker then
		activeByAttacker[reverse.attacker] = nil
	end
	activeByTarget[player] = nil
end)

return GrappleHandler