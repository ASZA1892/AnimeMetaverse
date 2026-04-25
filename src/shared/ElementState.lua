-- src/shared/ElementState.lua
-- Server-authoritative chakra pool and element ownership tracking.
-- Server: full read/write API, player lifecycle hooks, seal expiry heartbeat.
-- Client: read-only local cache for LocalPlayer, kept in sync via ElementRemote pushes.
-- NOTE: Chakra regen logic lives in ElementRegenerator.server.lua — not here.
--       This module owns the data and mutations. Regenerator owns the regen tick.

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

local MAX_CHAKRA  = Constants.MAX_CHAKRA       or 100
local REGEN_DELAY = Constants.CHAKRA_REGEN_DELAY or 2
local TICK_RATE   = 0.1  -- heartbeat interval for seal expiry only

local ElementState = {}

-- ─────────────────────────────────────────────
-- ElementRemote setup
-- Server creates it; client waits for it.
-- Same pattern as CombatRemote in CombatHandler.
-- ─────────────────────────────────────────────

local ElementRemote

if IS_SERVER then
    ElementRemote = ReplicatedStorage:FindFirstChild("ElementRemote")
    if not ElementRemote then
        ElementRemote = Instance.new("RemoteEvent")
        ElementRemote.Name = "ElementRemote"
        ElementRemote.Parent = ReplicatedStorage
    end
else
    ElementRemote = ReplicatedStorage:WaitForChild("ElementRemote", 10)
    if not ElementRemote then
        warn("[ElementState] ElementRemote not found after 10s — client cache will rely on defaults until server push arrives")
    end
end

-- ─────────────────────────────────────────────
-- Debug helper
-- ─────────────────────────────────────────────

local function dbg(...)
    if Constants and Constants.DEBUG then
        print("[ElementState]", ...)
    end
end

-- ─────────────────────────────────────────────
-- SERVER STATE
-- Per-player data keyed by UserId.
-- Only populated on the server.
-- ─────────────────────────────────────────────

local playerData = {}  -- [userId] = data table

local function defaultData()
    return {
        chakra              = MAX_CHAKRA,
        affinity            = nil,  -- string e.g. "Fire", nil for Wanderer
        knownElements       = {},   -- { ["Fire"] = true, ... }
        seals               = {},   -- { ["Fire"] = expiresAt (tick), ... }
        regenPausedUntil    = 0,    -- tick() timestamp; 0 = regen active
        techniqueUsedAt     = 0,    -- tick() of last technique fire (for post-use pause)
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
-- Fires current state snapshot to the owning client.
-- Called on all mutations and by ElementRegenerator during regen ticks.
-- ─────────────────────────────────────────────

local function pushToClient(player)
    if not IS_SERVER or not ElementRemote then return end
    local data = playerData[player.UserId]
    if not data then return end

    local now = tick()
    local activeSeals = {}
    for element, expiresAt in pairs(data.seals) do
        if expiresAt > now then
            activeSeals[element] = true  -- client only needs sealed/not sealed
        end
    end

    ElementRemote:FireClient(player, "STATE_UPDATE", {
        chakra        = math.floor(data.chakra + 0.5),  -- round for clean UI display
        affinity      = data.affinity,
        knownElements = data.knownElements,
        seals         = activeSeals,
    })
end

-- Exposed so ElementRegenerator can push after regen ticks
-- without needing direct access to playerData internals.
function ElementState.PushToClient(player)
    pushToClient(player)
end

-- ─────────────────────────────────────────────
-- CLIENT STATE
-- Local cache for the LocalPlayer only.
-- Updated whenever STATE_UPDATE arrives from server.
-- ─────────────────────────────────────────────

local localCache = {
    chakra        = MAX_CHAKRA,
    affinity      = nil,
    knownElements = {},
    seals         = {},
}

if not IS_SERVER and ElementRemote then
    ElementRemote.OnClientEvent:Connect(function(action, data)
        if action == "STATE_UPDATE" then
            localCache.chakra        = data.chakra
            localCache.affinity      = data.affinity
            localCache.knownElements = data.knownElements
            localCache.seals         = data.seals
        end
    end)
end

-- ─────────────────────────────────────────────
-- PUBLIC READ API
-- Identical signatures on server (authoritative) and client (cache).
-- ─────────────────────────────────────────────

function ElementState.GetChakra(player)
    if IS_SERVER then
        local data = playerData[player and player.UserId]
        return data and data.chakra or 0
    end
    return localCache.chakra
end

function ElementState.GetAffinity(player)
    if IS_SERVER then
        local data = playerData[player and player.UserId]
        return data and data.affinity or nil
    end
    return localCache.affinity
end

function ElementState.KnowsElement(player, element)
    if IS_SERVER then
        local data = playerData[player and player.UserId]
        return data ~= nil and data.knownElements[element] == true
    end
    return localCache.knownElements[element] == true
end

function ElementState.GetKnownElements(player)
    if IS_SERVER then
        local data = playerData[player and player.UserId]
        if not data then return {} end
        local result = {}
        for el in pairs(data.knownElements) do
            table.insert(result, el)
        end
        return result
    end
    local result = {}
    for el in pairs(localCache.knownElements) do
        table.insert(result, el)
    end
    return result
end

function ElementState.IsElementSealed(player, element)
    if IS_SERVER then
        local data = playerData[player and player.UserId]
        if not data then return false end
        local expiresAt = data.seals[element]
        return expiresAt ~= nil and tick() < expiresAt
    end
    return localCache.seals[element] == true
end

function ElementState.HasEnoughChakra(player, amount)
    return ElementState.GetChakra(player) >= (tonumber(amount) or 0)
end

-- Exposed to ElementRegenerator so it can read regen pause state
-- without coupling to internal data structure.
function ElementState.GetRegenData(player)
    if not IS_SERVER then return nil end
    local data = playerData[player and player.UserId]
    if not data then return nil end
    return {
        chakra           = data.chakra,
        regenPausedUntil = data.regenPausedUntil,
        techniqueUsedAt  = data.techniqueUsedAt,
    }
end

-- ─────────────────────────────────────────────
-- SERVER WRITE API
-- All mutations are server-only.
-- Each pushes to client immediately after changing state.
-- ─────────────────────────────────────────────

function ElementState.SetChakra(player, value)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    data.chakra = math.clamp(tonumber(value) or 0, 0, MAX_CHAKRA)
    pushToClient(player)
end

-- Returns true if deduction succeeded, false if insufficient chakra.
function ElementState.DeductChakra(player, amount)
    if not IS_SERVER then return false end
    local data = getOrCreate(player)
    local cost = tonumber(amount) or 0
    if data.chakra < cost then
        dbg(player.Name, "insufficient chakra — have:", data.chakra, "need:", cost)
        return false
    end
    data.chakra         = math.clamp(data.chakra - cost, 0, MAX_CHAKRA)
    data.techniqueUsedAt = tick()  -- triggers post-use regen pause in ElementRegenerator
    dbg(player.Name, "chakra deducted:", cost, "| remaining:", data.chakra)
    pushToClient(player)
    return true
end

function ElementState.AddChakra(player, amount)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    data.chakra = math.clamp(data.chakra + (tonumber(amount) or 0), 0, MAX_CHAKRA)
    pushToClient(player)
end

-- Direct write used by ElementRegenerator during regen ticks.
-- Does NOT push to client — Regenerator controls its own push throttle.
function ElementState.SetChakraSilent(player, value)
    if not IS_SERVER then return end
    local data = playerData[player and player.UserId]
    if not data then return end
    data.chakra = math.clamp(tonumber(value) or 0, 0, MAX_CHAKRA)
end

function ElementState.SetAffinity(player, element)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    data.affinity = element
    if element then
        data.knownElements[element] = true
    end
    dbg(player.Name, "affinity set →", tostring(element))
    pushToClient(player)
end

function ElementState.UnlockElement(player, element)
    if not IS_SERVER then return end
    if not element then return end
    local data = getOrCreate(player)
    data.knownElements[element] = true
    dbg(player.Name, "element unlocked →", element)
    pushToClient(player)
end

function ElementState.SealElement(player, element, duration)
    if not IS_SERVER then return end
    if not element then return end
    local data = getOrCreate(player)
    local d = tonumber(duration) or 6
    data.seals[element] = tick() + d
    dbg(player.Name, "element sealed →", element, "for", d, "seconds")
    pushToClient(player)
end

function ElementState.ClearSeal(player, element)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    data.seals[element] = nil
    pushToClient(player)
end

-- Called by CombatHandler after damage lands on a player.
-- Pauses chakra regen for REGEN_DELAY seconds.
function ElementState.PauseRegen(player)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    data.regenPausedUntil = tick() + REGEN_DELAY
end

function ElementState.ResetOnSpawn(player)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    data.chakra          = MAX_CHAKRA
    data.seals           = {}
    data.regenPausedUntil = 0
    data.techniqueUsedAt  = 0
    dbg(player.Name, "session state reset on spawn")
    pushToClient(player)
end

-- ─────────────────────────────────────────────
-- PLAYER LIFECYCLE (server only)
-- ─────────────────────────────────────────────

local function onPlayerAdded(player)
    getOrCreate(player)
    dbg(player.Name, "element data initialised")

    player.CharacterAdded:Connect(function()
        ElementState.ResetOnSpawn(player)
    end)
end

local function onPlayerRemoving(player)
    -- Phase 3: save affinity + knownElements to DataStore here
    playerData[player.UserId] = nil
    dbg(player.Name, "element data cleaned up")
end

if IS_SERVER then
    for _, player in ipairs(Players:GetPlayers()) do
        onPlayerAdded(player)
    end
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)
end

-- ─────────────────────────────────────────────
-- SERVER HEARTBEAT — SEAL EXPIRY ONLY
-- Regen has moved to ElementRegenerator.server.lua.
-- This heartbeat only cleans up expired seals and pushes
-- to client immediately when a seal drops.
-- ─────────────────────────────────────────────

if IS_SERVER then
    task.spawn(function()
        while true do
            local now = tick()

            for userId, data in pairs(playerData) do
                local sealChanged = false

                for element, expiresAt in pairs(data.seals) do
                    if now >= expiresAt then
                        data.seals[element] = nil
                        sealChanged = true
                        dbg("seal expired — userId:", userId, "element:", element)
                    end
                end

                if sealChanged then
                    local player = Players:GetPlayerByUserId(userId)
                    if player then
                        pushToClient(player)
                    end
                end
            end

            task.wait(TICK_RATE)
        end
    end)
end

print("✅ ElementState loaded (" .. (IS_SERVER and "server" or "client") .. ")")

return ElementState