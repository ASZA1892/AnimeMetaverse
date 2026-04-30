-- src/server/Combat/DashHandler.lua
-- Server-side dash validation and confirmation

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants     = require(ReplicatedStorage.Shared.Types.constants)
local CombatActions = require(ReplicatedStorage.Shared.Types.CombatActions)
local StaminaState  = require(ReplicatedStorage.Shared.StaminaState)

local DashHandler = {}

local lastDashAt = setmetatable({}, { __mode = "k" })

local function dbg(...)
    if Constants.DEBUG then
        print("[DashHandler]", ...)
    end
end

function DashHandler.ProcessDash(player, data, CombatStateMachine, CombatRemote)
    if type(data) ~= "table" then return end

    local dashType = data.dashType or "quick"
    local direction = data.direction or "forward"
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

    -- Resolve stamina cost by dash type
    local cost
    if dashType == "full" then
        cost = Constants.DASH_STAMINA_FULL   or 28
    elseif dashType == "medium" then
        cost = Constants.DASH_STAMINA_MEDIUM or 18
    else
        cost = Constants.DASH_STAMINA_QUICK  or 10
    end

    -- Server-authoritative stamina check and deduction
    if not StaminaState.Deduct(player, cost) then
        dbg(player.Name, "dash rejected: insufficient stamina (need", cost, "have", StaminaState.GetStamina(player), ")")
        return
    end

    -- Set dashing state
    local iframeDuration = Constants.DASH_IFRAMES_QUICK or 0.1
    CombatStateMachine.TrySetState(player, "Dashing", {
        expiresAt = now + iframeDuration
    })

    lastDashAt[player] = now

    dbg(player.Name, "dash confirmed | type:", dashType, "cost:", cost, "stamina remaining:", StaminaState.GetStamina(player))

    -- Confirm to client
    CombatRemote:FireClient(player, CombatActions.ServerToClient.DASH_CONFIRMED, {
        direction = direction,
        dashType  = dashType,
        speed     = 80,
        duration  = 0.12,
    })
end

Players.PlayerRemoving:Connect(function(player)
    lastDashAt[player] = nil
end)

return DashHandler