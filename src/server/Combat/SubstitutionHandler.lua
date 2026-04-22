-- src/server/Combat/SubstitutionHandler.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Types.constants)
local CombatActions = require(ReplicatedStorage.Shared.Types.CombatActions)

local SubstitutionHandler = {}

local lastSubAt = setmetatable({}, { __mode = "k" })
local SUB_COOLDOWN = 8

local function dbg(...)
	if Constants.DEBUG then
		print("[SubstitutionHandler]", ...)
	end
end

function SubstitutionHandler.ProcessSubstitution(player, data, CombatStateMachine, CombatRemote)
	local now = tick()
	local last = lastSubAt[player] or 0
	if now - last < SUB_COOLDOWN then
		dbg(player.Name, "substitution on cooldown")
		CombatRemote:FireClient(player, CombatActions.ServerToClient.SUBSTITUTION_FAILED, {
			reason = "cooldown"
		})
		return
	end

	local character = player.Character
	if not character or not character.PrimaryPart then
		dbg(player.Name, "no character")
		return
	end

	-- Get attacker position from data
	local attackerPosition
	if data and data.attacker and typeof(data.attacker) == "Instance" then
		local attackerChar = data.attacker.Character
		if attackerChar and attackerChar.PrimaryPart then
			attackerPosition = attackerChar.PrimaryPart.Position
		end
	end

	if not attackerPosition then
		dbg(player.Name, "could not resolve attacker position")
		CombatRemote:FireClient(player, CombatActions.ServerToClient.SUBSTITUTION_FAILED, {
			reason = "no_attacker"
		})
		return
	end

	lastSubAt[player] = now

	-- Force player to Idle state
	if CombatStateMachine then
		CombatStateMachine.ForceState(player, "Idle")
	end

	dbg(player.Name, "substitution confirmed, attacker at", attackerPosition)

	CombatRemote:FireClient(player, CombatActions.ServerToClient.SUBSTITUTION_CONFIRMED, {
		attackerPosition = attackerPosition,
	})
end

Players.PlayerRemoving:Connect(function(player)
	lastSubAt[player] = nil
end)

return SubstitutionHandler