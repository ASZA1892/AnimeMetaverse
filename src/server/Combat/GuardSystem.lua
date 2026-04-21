local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Types.constants)

local GuardSystem = {}

local blockingPlayers = setmetatable({}, { __mode = "k" })
local lastParryAt = setmetatable({}, { __mode = "k" })

local PARRY_WINDOW = Constants.PARRY_WINDOW or 0.2

function GuardSystem.StartBlocking(player)
	if not player then
		return
	end

	blockingPlayers[player] = true
end

function GuardSystem.StopBlocking(player)
	if not player then
		return
	end

	blockingPlayers[player] = nil
end

function GuardSystem.IsBlocking(player)
	return blockingPlayers[player] == true
end

function GuardSystem.RecordParry(player)
	if not player then
		return false
	end

	local now = tick()
	local last = lastParryAt[player]
	if last and (now - last) < PARRY_WINDOW then
		return false
	end

	lastParryAt[player] = now
	return true
end

function GuardSystem.ProcessHit(attacker, target, damage, move)
	local _ = attacker
	local __ = move

	local incomingDamage = tonumber(damage) or 0
	if incomingDamage <= 0 then
		return 0, false, false
	end

	if not target then
		return incomingDamage, false, false
	end

	local now = tick()
	local lastParry = lastParryAt[target]
	if lastParry and (now - lastParry) <= PARRY_WINDOW then
		return 0, true, false
	end

	if GuardSystem.IsBlocking(target) then
		return 0, false, false
	end

	return incomingDamage, false, false
end

return GuardSystem
