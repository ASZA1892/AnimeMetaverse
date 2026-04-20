-- src/server/Combat/CombatStateMachine.lua
-- Server-side combat state management with event hooks, timed state support, and safe APIs

local Players = game:GetService("Players")

local CombatStateMachine = {}

-- Development debug toggle (can be changed at runtime)
local DEBUG = true

-- Core state enum
CombatStateMachine.States = {
    Idle = "Idle",
    Attacking = "Attacking",
    Blocking = "Blocking",
    Dashing = "Dashing",
    Stunned = "Stunned",
    Grappling = "Grappling",
}

local DEFAULT_STATE = CombatStateMachine.States.Idle

-- Strict transition rules
local TRANSITIONS = {
    [CombatStateMachine.States.Idle] = {
        [CombatStateMachine.States.Attacking] = true,
        [CombatStateMachine.States.Blocking] = true,
        [CombatStateMachine.States.Dashing] = true,
        [CombatStateMachine.States.Grappling] = true,
    },
    [CombatStateMachine.States.Attacking] = {
        [CombatStateMachine.States.Idle] = true,
        [CombatStateMachine.States.Dashing] = true,
        [CombatStateMachine.States.Stunned] = true,
        [CombatStateMachine.States.Grappling] = true,
    },
    [CombatStateMachine.States.Blocking] = {
        [CombatStateMachine.States.Idle] = true,
        [CombatStateMachine.States.Dashing] = true,
        [CombatStateMachine.States.Stunned] = true,
    },
    [CombatStateMachine.States.Dashing] = {
        [CombatStateMachine.States.Idle] = true,
        [CombatStateMachine.States.Attacking] = true,
        [CombatStateMachine.States.Blocking] = true,
        [CombatStateMachine.States.Grappling] = true,
    },
    [CombatStateMachine.States.Stunned] = {
        [CombatStateMachine.States.Idle] = true,
    },
    [CombatStateMachine.States.Grappling] = {
        [CombatStateMachine.States.Idle] = true,
        [CombatStateMachine.States.Stunned] = true,
    },
}

-- Per-player data keyed by UserId
local playerStates = {}

-- State change listeners management
local stateChangeListeners = {}
local nextListenerId = 0

-- Simple debug printer
local function debugLog(...)
    if DEBUG then
        print("[CombatStateMachine]", ...)
    end
end

-- Validate a state string
local function isValidState(state)
    for _, v in pairs(CombatStateMachine.States) do
        if v == state then
            return true
        end
    end
    return false
end

-- Validate player argument
local function isValidPlayer(player)
    return player and typeof(player) == "Instance" and player:IsA("Player") and player.UserId and player.UserId > 0
end

-- Airborne helper
local function isAirborneState(humanoidState)
    return humanoidState == Enum.HumanoidStateType.Freefall
        or humanoidState == Enum.HumanoidStateType.Jumping
        or humanoidState == Enum.HumanoidStateType.FallingDown
        or humanoidState == Enum.HumanoidStateType.Flying
end

-- Create or fetch per-player data
local function getOrCreatePlayerData(player)
    local key = player.UserId
    local data = playerStates[key]
    if data then
        return data
    end

    data = {
        Player = player,
        State = DEFAULT_STATE,
        IsAirborne = false,
        HumanoidConnection = nil,
        CharacterConnection = nil,
        ExpiresAt = 0,    -- tick() timestamp when state expires (0 = none)
        Meta = {},
        Locked = false,   -- simple per-player lock to avoid concurrent transitions
    }
    playerStates[key] = data
    return data
end

local function disconnectHumanoidConnection(data)
    if data and data.HumanoidConnection then
        pcall(function() data.HumanoidConnection:Disconnect() end)
        data.HumanoidConnection = nil
    end
end

local function bindHumanoid(player, humanoid)
    local data = getOrCreatePlayerData(player)
    disconnectHumanoidConnection(data)

    data.IsAirborne = isAirborneState(humanoid:GetState())

    data.HumanoidConnection = humanoid.StateChanged:Connect(function(_, newState)
        local airborne = isAirborneState(newState)
        if data.IsAirborne ~= airborne then
            data.IsAirborne = airborne
            debugLog(player.Name, "IsAirborne =", airborne)
        end
    end)
end

local function onCharacterAdded(player, character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        humanoid = character:WaitForChild("Humanoid", 10)
    end

    if humanoid then
        bindHumanoid(player, humanoid)
    end
end

local function trackPlayer(player)
    if not isValidPlayer(player) then return end
    local data = getOrCreatePlayerData(player)

    if data.CharacterConnection then
        pcall(function() data.CharacterConnection:Disconnect() end)
        data.CharacterConnection = nil
    end

    data.CharacterConnection = player.CharacterAdded:Connect(function(character)
        onCharacterAdded(player, character)
    end)

    if player.Character then
        onCharacterAdded(player, player.Character)
    end
end

local function cleanupPlayer(player)
    if not isValidPlayer(player) then return end
    local key = player.UserId
    local data = playerStates[key]
    if not data then return end

    disconnectHumanoidConnection(data)

    if data.CharacterConnection then
        pcall(function() data.CharacterConnection:Disconnect() end)
        data.CharacterConnection = nil
    end

    playerStates[key] = nil
    debugLog(player.Name, "state data cleaned up")
end

-- Public API: read-only snapshot of player data
function CombatStateMachine.GetPlayerData(player)
    if not isValidPlayer(player) then return nil end
    local data = playerStates[player.UserId]
    if not data then return nil end
    return {
        State = data.State,
        IsAirborne = data.IsAirborne,
        ExpiresAt = data.ExpiresAt,
        Meta = data.Meta and table.clone(data.Meta) or {},
    }
end

function CombatStateMachine.GetState(player)
    local d = CombatStateMachine.GetPlayerData(player)
    return d and d.State or DEFAULT_STATE
end

function CombatStateMachine.GetIsAirborne(player)
    local d = CombatStateMachine.GetPlayerData(player)
    return d and d.IsAirborne or false
end

function CombatStateMachine.GetExpiresAt(player)
    local d = CombatStateMachine.GetPlayerData(player)
    return d and d.ExpiresAt or 0
end

function CombatStateMachine.GetMeta(player)
    local d = CombatStateMachine.GetPlayerData(player)
    return d and d.Meta or {}
end

-- Check if a transition is allowed and not blocked by expiry
function CombatStateMachine.CanTransition(player, newState)
    if not isValidPlayer(player) then
        return false, "invalid_player"
    end
    if not isValidState(newState) then
        return false, "invalid_state"
    end

    local data = getOrCreatePlayerData(player)
    local currentState = data.State
    local allowed = TRANSITIONS[currentState]
    local can = allowed and allowed[newState] == true

    -- If current state has an expiry and hasn't expired, block transitions (unless forced)
    if can and data.ExpiresAt and data.ExpiresAt > 0 and tick() < data.ExpiresAt then
        return false, "state_not_expired"
    end

    return can and true or false, can and nil or "invalid_transition"
end

-- Internal helper to notify listeners; runs callbacks asynchronously
local function notifyStateChange(player, oldState, newState, meta)
    for id, listener in pairs(stateChangeListeners) do
        task.spawn(function()
            local ok, err = pcall(listener.callback, player, oldState, newState, meta or {})
            if not ok then
                debugLog("StateChange listener error (id=" .. tostring(id) .. "):", err)
            end
        end)
    end
end

-- Try to set state with optional meta { expiresAt = tick() + duration, ... }
function CombatStateMachine.TrySetState(player, newState, meta)
    if not isValidPlayer(player) then
        return false, "invalid_player"
    end
    if not isValidState(newState) then
        return false, "invalid_state"
    end

    local data = getOrCreatePlayerData(player)

    -- Simple per-player lock to reduce race conditions
    if data.Locked then
        return false, "locked"
    end

    local can, reason = CombatStateMachine.CanTransition(player, newState)
    if not can then
        debugLog(player.Name, "blocked transition", data.State, "->", newState, "reason:", reason)
        return false, reason
    end

    data.Locked = true
    local ok, err = pcall(function()
        local oldState = data.State
        data.State = newState
        data.ExpiresAt = meta and meta.expiresAt or 0
        data.Meta = meta or {}
        debugLog(player.Name, "state changed", oldState, "->", newState, meta and "with meta" or "")
        notifyStateChange(player, oldState, newState, data.Meta)
    end)
    data.Locked = false

    if not ok then
        debugLog("TrySetState error:", err)
        return false, "internal_error"
    end

    return true, nil
end

-- Force state change (bypasses CanTransition checks)
function CombatStateMachine.ForceState(player, newState, meta)
    if not isValidPlayer(player) then
        return false, "invalid_player"
    end
    if not isValidState(newState) then
        return false, "invalid_state"
    end

    local data = getOrCreatePlayerData(player)
    local oldState = data.State
    data.State = newState
    data.ExpiresAt = meta and meta.expiresAt or 0
    data.Meta = meta or {}
    debugLog(player.Name, "force state", oldState, "->", newState)
    notifyStateChange(player, oldState, newState, data.Meta)
    return true, nil
end

function CombatStateMachine.IsStunned(player)
    return CombatStateMachine.GetState(player) == CombatStateMachine.States.Stunned
end

-- Backwards compatibility alias
CombatStateMachine.IsDisabled = CombatStateMachine.IsStunned

function CombatStateMachine.CanAttack(player)
    local state = CombatStateMachine.GetState(player)
    return state == CombatStateMachine.States.Idle or state == CombatStateMachine.States.Attacking
end

-- Listener management: returns a handle with Disconnect()
function CombatStateMachine.OnStateChanged(callback)
    if type(callback) ~= "function" then
        error("OnStateChanged expects a function")
    end
    nextListenerId = nextListenerId + 1
    local id = nextListenerId
    stateChangeListeners[id] = { callback = callback }
    local handle = {
        Disconnect = function()
            stateChangeListeners[id] = nil
        end
    }
    return handle
end

-- Utility: remove listener by id (if needed)
function CombatStateMachine.RemoveStateChangedListener(handle)
    if type(handle) == "table" and type(handle.Disconnect) == "function" then
        handle:Disconnect()
        return true
    end
    return false
end

-- Toggle debug at runtime
function CombatStateMachine.SetDebug(value)
    DEBUG = not not value
end

function CombatStateMachine.GetAllStates()
    local snapshot = {}
    for userId, data in pairs(playerStates) do
        local playerName = data.Player and data.Player.Name or ("UserId:" .. tostring(userId))
        snapshot[playerName] = {
            State = data.State,
            IsAirborne = data.IsAirborne,
            ExpiresAt = data.ExpiresAt,
            Meta = data.Meta and table.clone(data.Meta) or {},
        }
    end
    return snapshot
end

-- Heartbeat: expire timed states and revert to DEFAULT_STATE
task.spawn(function()
    while true do
        local now = tick()
        for userId, data in pairs(playerStates) do
            if data and data.ExpiresAt and data.ExpiresAt > 0 and now >= data.ExpiresAt then
                if data.State ~= DEFAULT_STATE then
                    local player = data.Player
                    local old = data.State
                    data.State = DEFAULT_STATE
                    data.ExpiresAt = 0
                    data.Meta = {}
                    debugLog(player and player.Name or ("UserId:" .. tostring(userId)), "state expired", old, "->", DEFAULT_STATE)
                    notifyStateChange(player, old, DEFAULT_STATE, {})
                end
            end
        end
        task.wait(0.25)
    end
end)

-- Initialize tracking for existing players
for _, player in ipairs(Players:GetPlayers()) do
    trackPlayer(player)
end

Players.PlayerAdded:Connect(trackPlayer)
Players.PlayerRemoving:Connect(cleanupPlayer)

-- Expose debug toggle for convenience
CombatStateMachine.SetDebug(DEBUG)

return CombatStateMachine
