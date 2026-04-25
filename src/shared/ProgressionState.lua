-- src/shared/ProgressionState.lua
-- Server-authoritative GPL and mastery tracking.
-- Server: full read/write API, player lifecycle hooks.
-- Client: read-only local cache, kept in sync via ProgressionRemote pushes.
-- DataStore persistence hookup deferred to Phase 3.

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

local STARTING_GPL = Constants.GPL_STARTING or 100

local ProgressionState = {}

-- ─────────────────────────────────────────────
-- ProgressionRemote setup
-- ─────────────────────────────────────────────

local ProgressionRemote

if IS_SERVER then
    ProgressionRemote = ReplicatedStorage:FindFirstChild("ProgressionRemote")
    if not ProgressionRemote then
        ProgressionRemote = Instance.new("RemoteEvent")
        ProgressionRemote.Name = "ProgressionRemote"
        ProgressionRemote.Parent = ReplicatedStorage
    end
else
    ProgressionRemote = ReplicatedStorage:WaitForChild("ProgressionRemote", 10)
    if not ProgressionRemote then
        warn("[ProgressionState] ProgressionRemote not found after 10s")
    end
end

-- ─────────────────────────────────────────────
-- Debug helper
-- ─────────────────────────────────────────────

local function dbg(...)
    if Constants and Constants.DEBUG then
        print("[ProgressionState]", ...)
    end
end

-- ─────────────────────────────────────────────
-- SERVER STATE
-- ─────────────────────────────────────────────

local playerData = {}  -- [userId] = data table

local function defaultData()
    return {
        gpl          = STARTING_GPL,
        honor        = 0,           -- -100 to +100
        mastery      = {},          -- [techniqueId] = { tier = 1, points = 0, resonance = 0 }
        sessionGPLGained = 0,       -- tracked for death penalty cap
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

local function pushToClient(player)
    if not IS_SERVER or not ProgressionRemote then return end
    local data = playerData[player.UserId]
    if not data then return end

    ProgressionRemote:FireClient(player, "STATE_UPDATE", {
        gpl    = data.gpl,
        honor  = data.honor,
        mastery = data.mastery,
    })
end

function ProgressionState.PushToClient(player)
    pushToClient(player)
end

-- ─────────────────────────────────────────────
-- CLIENT STATE
-- ─────────────────────────────────────────────

local localCache = {
    gpl     = STARTING_GPL,
    honor   = 0,
    mastery = {},
}

if not IS_SERVER and ProgressionRemote then
    ProgressionRemote.OnClientEvent:Connect(function(action, data)
        if action == "STATE_UPDATE" then
            localCache.gpl     = data.gpl
            localCache.honor   = data.honor
            localCache.mastery = data.mastery
        end
    end)
end

-- ─────────────────────────────────────────────
-- PUBLIC READ API
-- ─────────────────────────────────────────────

function ProgressionState.GetGPL(player)
    if IS_SERVER then
        local data = playerData[player and player.UserId]
        return data and data.gpl or STARTING_GPL
    end
    return localCache.gpl
end

function ProgressionState.GetHonor(player)
    if IS_SERVER then
        local data = playerData[player and player.UserId]
        return data and data.honor or 0
    end
    return localCache.honor
end

function ProgressionState.GetMastery(player, techniqueId)
    if IS_SERVER then
        local data = playerData[player and player.UserId]
        if not data then return nil end
        return data.mastery[techniqueId]
    end
    return localCache.mastery[techniqueId]
end

function ProgressionState.GetSessionGPLGained(player)
    if not IS_SERVER then return 0 end
    local data = playerData[player and player.UserId]
    return data and data.sessionGPLGained or 0
end

-- ─────────────────────────────────────────────
-- SERVER WRITE API
-- ─────────────────────────────────────────────

function ProgressionState.SetGPL(player, value)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    local clamped = math.max(0, math.floor(tonumber(value) or 0))
    data.gpl = clamped
    dbg(player.Name, "GPL set →", clamped)
    pushToClient(player)
end

function ProgressionState.AddGPL(player, amount)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    local gain = math.max(0, math.floor(tonumber(amount) or 0))
    data.gpl = data.gpl + gain
    data.sessionGPLGained = data.sessionGPLGained + gain
    dbg(player.Name, "GPL +" .. gain, "→", data.gpl)
    pushToClient(player)
end

function ProgressionState.DeductGPL(player, amount)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    local loss = math.max(0, math.floor(tonumber(amount) or 0))
    data.gpl = math.max(0, data.gpl - loss)
    dbg(player.Name, "GPL -" .. loss, "→", data.gpl)
    pushToClient(player)
end

function ProgressionState.SetHonor(player, value)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    data.honor = math.clamp(math.floor(tonumber(value) or 0), -100, 100)
    dbg(player.Name, "Honor set →", data.honor)
    pushToClient(player)
end

function ProgressionState.AddHonor(player, amount)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    data.honor = math.clamp(data.honor + math.floor(tonumber(amount) or 0), -100, 100)
    dbg(player.Name, "Honor →", data.honor)
    pushToClient(player)
end

-- Initialise mastery entry for a technique if not already tracked.
-- tier starts at Raw (1), points and resonance start at 0.
function ProgressionState.InitMastery(player, techniqueId)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    if not data.mastery[techniqueId] then
        data.mastery[techniqueId] = { tier = 1, points = 0, resonance = 0 }
        dbg(player.Name, "mastery initialised →", techniqueId)
        pushToClient(player)
    end
end

-- Add mastery points to a technique. Tier advancement handled by MasteryTracker.
function ProgressionState.AddMasteryPoints(player, techniqueId, points)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    if not data.mastery[techniqueId] then
        ProgressionState.InitMastery(player, techniqueId)
    end
    data.mastery[techniqueId].points = data.mastery[techniqueId].points + (tonumber(points) or 0)
    dbg(player.Name, techniqueId, "mastery points →", data.mastery[techniqueId].points)
    pushToClient(player)
end

function ProgressionState.SetMasteryTier(player, techniqueId, tier)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    if not data.mastery[techniqueId] then
        ProgressionState.InitMastery(player, techniqueId)
    end
    data.mastery[techniqueId].tier = math.clamp(math.floor(tonumber(tier) or 1), 1, 5)
    dbg(player.Name, techniqueId, "mastery tier →", data.mastery[techniqueId].tier)
    pushToClient(player)
end

function ProgressionState.AddResonance(player, techniqueId, amount)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    if not data.mastery[techniqueId] then
        ProgressionState.InitMastery(player, techniqueId)
    end
    data.mastery[techniqueId].resonance = data.mastery[techniqueId].resonance + (tonumber(amount) or 0)
    dbg(player.Name, techniqueId, "resonance →", data.mastery[techniqueId].resonance)
    pushToClient(player)
end

-- Called on character spawn — resets session GPL gain counter.
-- GPL and mastery persist (DataStore hookup Phase 3).
function ProgressionState.ResetOnSpawn(player)
    if not IS_SERVER then return end
    local data = getOrCreate(player)
    data.sessionGPLGained = 0
    dbg(player.Name, "session GPL counter reset")
end

-- ─────────────────────────────────────────────
-- PLAYER LIFECYCLE (server only)
-- ─────────────────────────────────────────────

local function onPlayerAdded(player)
    getOrCreate(player)
    dbg(player.Name, "progression data initialised — GPL:", STARTING_GPL)

    player.CharacterAdded:Connect(function()
        ProgressionState.ResetOnSpawn(player)
    end)
end

local function onPlayerRemoving(player)
    -- Phase 3: save GPL, honor, mastery to DataStore here before clearing
    playerData[player.UserId] = nil
    dbg(player.Name, "progression data cleaned up")
end

if IS_SERVER then
    for _, player in ipairs(Players:GetPlayers()) do
        onPlayerAdded(player)
    end
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)
end

print("✅ ProgressionState loaded (" .. (IS_SERVER and "server" or "client") .. ")")

return ProgressionState