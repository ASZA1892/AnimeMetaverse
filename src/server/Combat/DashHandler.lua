-- src/server/Combat/DashHandler.lua
-- Server-side dash validation and confirmation

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Types.constants)
local CombatActions = require(ReplicatedStorage.Shared.Types.CombatActions)

local DashHandler = {}

local lastDashAt = setmetatable({}, { __mode = "k" })

local function dbg(...)
	if Constants.DEBUG then
		print("[DashHandler]", ...)
	end
end

function DashHandler.ProcessDash(player, data, CombatStateMachine, CombatRemote)
	if type(data) ~= "table" then return end

	local direction = data.direction or "forward"
	local dashType = data.dashType or "quick"
	local now = tick()

	-- Rate limit
	local last = lastDashAt[player] or 0
	local cooldown = Constants.DASH_COOLDOWN or 0.8
	if now - last < cooldown then
		dbg(player.Name, "dash rate limited")
		return
	end

	-- Validate state
	if not CombatStateMachine.CanTransition(player, "Dashing") then
		dbg(player.Name, "cannot dash from state:", CombatStateMachine.GetState(player))
		return
	end

	-- Set dashing state
	local iframeDuration = Constants.DASH_IFRAMES_QUICK or 0.1
	CombatStateMachine.TrySetState(player, "Dashing", {
		expiresAt = now + iframeDuration
	})

	lastDashAt[player] = now

	dbg(player.Name, "dash confirmed | direction:", direction, "type:", dashType)

	-- Confirm to client
	CombatRemote:FireClient(player, CombatActions.ServerToClient.DASH_CONFIRMED, {
		direction = direction,
		dashType = dashType,
		speed = 80,
		duration = 0.12,
		stamina = Constants.MAX_STAMINA,
	})
end

Players.PlayerRemoving:Connect(function(player)
	lastDashAt[player] = nil
end)

return DashHandler