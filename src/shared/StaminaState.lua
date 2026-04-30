-- src/shared/StaminaState.lua
-- Server-authoritative stamina tracking.
-- Server: full read/write API, regen heartbeat, lifecycle hooks.
-- Client: read-only local cache, fed by StaminaRemote pushes.
--
-- Refactored from Phase 1 placeholder. The Phase 1 version allowed
-- client-side mutations for UI prediction. This version is locked down:
-- the client cache exists ONLY for UI reads, never affects gameplay.

local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IS_SERVER = RunService:IsServer()

local Constants = require(
    ReplicatedStorage
        :WaitForChild("Shared", 5)
        :WaitForChild("Types", 5)
        :WaitForChild("constants", 5)
)

local MAX_STAMINA           = Constants.MAX_STAMINA           or 100
local REGEN_RATE            = Constants.STAMINA_REGEN_RATE    or 15
local REGEN_RATE_SPRINT     = Constants.STAMINA_REGEN_SPRINT  or 5
local REGEN_PAUSE_DURATION  = Constants.STAMINA_REGEN_PAUSE   or 2.0

local StaminaState = {}

-- ─────────────────────────────────────────────
-- StaminaRemote setup
-- ─────────────────────────────────────────────

local StaminaRemote
if IS_SERVER then
    StaminaRemote = ReplicatedStorage:FindFirstChild("StaminaRemote")
    if not StaminaRemote then
        StaminaRemote = Instance.new("RemoteEvent")
        StaminaRemote.Name = "StaminaRemote"
        StaminaRemote.Parent = ReplicatedStorage
    end
else
    StaminaRemote = ReplicatedStorage:WaitForChild("StaminaRemote", 10)
end

local function dbg(...)
    if Constants and Constants.DEBUG then
        print("[StaminaState]", ...)
    end
end

-- ─────────────────────────────────────────────
-- SERVER STATE
-- ─────────────────────────────────────────────

-- playerData[userId] = {
--     stamina           = number,    -- current value 0..MAX_STAMINA
--     regenPausedUntil  = number,    -- os.clock() timestamp; regen blocked until this time
--     isSprinting       = boolean,   -- if true, regen rate uses sprint rate
-- }
local playerData = {}

local function defaultData()
    return {
        stamina          = MAX_STAMINA,
        regenPausedUntil = 0,
        isSprinting      = false,
    }
end

local function getOrCreate(player)
    local key = player.UserId
    if not playerData[key] then
        playerData[key] = defaultData()
    end
    return playerData[key]
end

-- ─────────────────────────────────────────────
-- SERVER → CLIENT PUSH
-- ─────────────────────────────────────────────

local lastPushAt = {}
local PUSH_INTERVAL = 0.1  -- 10Hz push limit per player

local function pushToClient(player, force)
    if not IS_SERVER or not StaminaRemote then return end
    local data = playerData[player.UserId]
    if not data then return end

    local now = os.clock()
    local last = lastPushAt[player.UserId] or 0
    if not force and (now - last) < PUSH_INTERVAL then return end
    lastPushAt[player.UserId] = now

    StaminaRemote:FireClient(player, "STATE_UPDATE", {
        stamina = data.stamina,
        max     = MAX_STAMINA,
    })
end

function StaminaState.PushToClient(player)
    pushToClient(player, true)
end

-- ─────────────────────────────────────────────
-- CLIENT STATE — read-only cache
-- ─────────────────────────────────────────────

local localCache = {
    stamina = MAX_STAMINA,
    max     = MAX_STAMINA,
}

if not IS_SERVER and StaminaRemote then
    StaminaRemote.OnClientEvent:Connect(function(action, data)
        if action == "STATE_UPDATE" and type(data) == "table" then
            localCache.stamina = data.stamina or localCache.stamina
            localCache.max     = data.max     or localCache.max
        end
    end)
end

-- ─────────────────────────────────────────────
-- PUBLIC READ API (works on both server and client)
-- ─────────────────────────────────────────────

function StaminaState.GetStamina(player)
    if IS_SERVER then
        local data = playerData[player and player.UserId]
        return data and data.stamina or MAX_STAMINA
    end
    return localCache.stamina
end

function StaminaState.GetMaxStamina()
    if IS_SERVER then return MAX_STAMINA end
    return localCache.max
end

function StaminaState.HasEnough(player, amount)
    if IS_SERVER then
        local data = playerData[player and player.UserId]
        if not data then return false end
        return data.stamina >= (tonumber(amount) or 0)
    end
    -- Client-side prediction read only — server still authoritative
    return localCache.stamina >= (tonumber(amount) or 0)
end

-- ─────────────────────────────────────────────
-- SERVER WRITE API (server only — silently no-ops on client)
-- ─────────────────────────────────────────────

-- Deduct stamina. Returns true on success, false if insufficient.
function StaminaState.Deduct(player, amount)
    if not IS_SERVER then
        warn("[StaminaState] Deduct called on client — ignored")
        return false
    end
    local data = getOrCreate(player)
    local cost = math.max(0, tonumber(amount) or 0)
    if data.stamina < cost then
        return false
    end
    data.stamina = math.max(0, data.stamina - cost)
    pushToClient(player, true)
    dbg(player.Name, "stamina -" .. cost, "→", data.stamina)
    return true
end

-- Restore stamina. Cannot exceed MAX_STAMINA.
function StaminaState.Restore(player, amount)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    local gain = math.max(0, tonumber(amount) or 0)
    data.stamina = math.min(MAX_STAMINA, data.stamina + gain)
    pushToClient(player, true)
end

-- Pause regen for REGEN_PAUSE_DURATION seconds. Stacks (always uses max of existing and new).
function StaminaState.PauseRegen(player, customDuration)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    local duration = tonumber(customDuration) or REGEN_PAUSE_DURATION
    local until_ = os.clock() + duration
    if until_ > data.regenPausedUntil then
        data.regenPausedUntil = until_
    end
end

-- Set sprint state for regen rate calculation.
function StaminaState.SetSprinting(player, isSprinting)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    data.isSprinting = isSprinting == true
end

-- Internal getter for the regenerator heartbeat (or for diagnostics)
function StaminaState.GetRegenData(player)
    if not IS_SERVER then return nil end
    return playerData[player and player.UserId]
end

-- Direct silent set without push — used by regen heartbeat to avoid push spam.
-- Caller should call PushToClient explicitly.
function StaminaState.SetSilent(player, value)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    data.stamina = math.clamp(tonumber(value) or 0, 0, MAX_STAMINA)
end

-- ─────────────────────────────────────────────
-- REGEN HEARTBEAT (server only)
-- ─────────────────────────────────────────────

if IS_SERVER then
    local TICK_RATE      = 0.1
    local REGEN_PER_TICK = TICK_RATE
    local accumulator    = 0
    local pushAccum      = {}

    RunService.Heartbeat:Connect(function(dt)
        accumulator = accumulator + dt
        if accumulator < TICK_RATE then return end
        accumulator = accumulator - TICK_RATE

        local now = os.clock()

        for _, player in ipairs(Players:GetPlayers()) do
            local data = playerData[player.UserId]
            if data and data.stamina < MAX_STAMINA and now >= data.regenPausedUntil then
                local rate = data.isSprinting and REGEN_RATE_SPRINT or REGEN_RATE
                local gained = rate * REGEN_PER_TICK
                data.stamina = math.min(MAX_STAMINA, data.stamina + gained)

                -- Throttled push so we don't spam the client every tick
                local last = pushAccum[player.UserId] or 0
                if (now - last) >= 0.5 then
                    pushAccum[player.UserId] = now
                    pushToClient(player, true)
                end
            end
        end
    end)
end

-- ─────────────────────────────────────────────
-- PLAYER LIFECYCLE (server only)
-- ─────────────────────────────────────────────

local function onPlayerAdded(player)
    getOrCreate(player)
    dbg(player.Name, "stamina initialised →", MAX_STAMINA)
    pushToClient(player, true)

    player.CharacterAdded:Connect(function()
        local data = getOrCreate(player)
        data.stamina = MAX_STAMINA
        data.regenPausedUntil = 0
        data.isSprinting = false
        pushToClient(player, true)
        dbg(player.Name, "stamina reset on spawn")
    end)
end

if IS_SERVER then
    for _, player in ipairs(Players:GetPlayers()) do
        onPlayerAdded(player)
    end
    -- Handle sprint state notifications from client
StaminaRemote.OnServerEvent:Connect(function(player, action, data)
    if action == "SET_SPRINT" and type(data) == "table" then
        StaminaState.SetSprinting(player, data.isSprinting == true)
    end
end)
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(function(player)
        playerData[player.UserId] = nil
        lastPushAt[player.UserId] = nil
    end)
end

print("✅ StaminaState loaded (" .. (IS_SERVER and "server" or "client") .. ")")

return StaminaState