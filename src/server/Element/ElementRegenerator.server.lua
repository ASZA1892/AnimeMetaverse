-- src/server/Element/ElementRegenerator.server.lua
-- Owns all state-based chakra regen logic.
-- Queries CombatStateMachine for player state each tick,
-- applies the correct regen rate, and pushes to client on a throttle.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared", 10)

local Constants          = require(sharedFolder:WaitForChild("Types", 5):WaitForChild("constants", 5))
local ElementState       = require(sharedFolder:WaitForChild("ElementState", 5))
local CombatStateMachine = require(game:GetService("ServerScriptService"):WaitForChild("Combat", 5):WaitForChild("CombatStateMachine", 5))

-- ─────────────────────────────────────────────
-- Constants
-- ─────────────────────────────────────────────

local MAX_CHAKRA      = Constants.MAX_CHAKRA                  or 100
local REGEN_IDLE      = Constants.CHAKRA_REGEN_IDLE           or 8
local REGEN_MOVING    = Constants.CHAKRA_REGEN_MOVING         or 5
local REGEN_SPRINT    = Constants.CHAKRA_REGEN_SPRINT         or 2
local REGEN_BLOCKING  = Constants.CHAKRA_REGEN_BLOCKING       or 2
local REGEN_CHARGING  = Constants.CHAKRA_REGEN_CHARGING       or 12
local POST_USE_PAUSE  = Constants.CHAKRA_REGEN_POST_USE       or 1.5
local PUSH_INTERVAL   = Constants.CHAKRA_REGEN_PUSH_INTERVAL  or 0.5
local HIT_PAUSE       = Constants.CHAKRA_REGEN_DELAY          or 2

local TICK_RATE       = 0.1  -- 10 ticks per second
local REGEN_PER_TICK  = TICK_RATE  -- multiplied by rate below each tick

-- ─────────────────────────────────────────────
-- Debug helper
-- ─────────────────────────────────────────────

local function dbg(...)
    if Constants.DEBUG then
        print("[ElementRegenerator]", ...)
    end
end

-- ─────────────────────────────────────────────
-- Per-player push throttle
-- Keyed by UserId. Prevents flooding client with
-- a remote event every 0.1s during passive regen.
-- ─────────────────────────────────────────────

local lastPushAt = {}  -- [userId] = tick()

-- ─────────────────────────────────────────────
-- Regen rate resolver
-- Reads CombatStateMachine state and character
-- WalkSpeed to determine correct regen rate.
-- Returns: regenRate (number), stateName (string for debug)
-- ─────────────────────────────────────────────

local function getRegenRate(player)
    local state = CombatStateMachine.GetState(player)

    -- Channeling / charge move — fastest regen but player is vulnerable
    if state == "Channeling" then
        return REGEN_CHARGING, "Channeling"
    end

    -- Blocking — slow regen while turtling
    if state == "Blocking" then
        return REGEN_BLOCKING, "Blocking"
    end

    -- Dashing or attacking — treat as sprint-tier (pressured, moving fast)
    if state == "Dashing" or state == "Attacking" then
        return REGEN_SPRINT, "Active"
    end

    -- Stunned or Grappling — no regen, fully compromised
    if state == "Stunned" or state == "Grappling" then
        return 0, "Suppressed"
    end

    -- Idle — check WalkSpeed to distinguish standing vs moving vs sprinting
    local character = player.Character
    if not character then
        return REGEN_IDLE, "Idle"
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return REGEN_IDLE, "Idle"
    end

    local speed = humanoid.WalkSpeed

    -- Sprint threshold matches SprintController (28 walkspeed)
    if speed >= 26 then
        return REGEN_SPRINT, "Sprinting"
    end

    -- Moving at normal walk speed
    if speed > 2 then
        return REGEN_MOVING, "Moving"
    end

    -- Standing still
    return REGEN_IDLE, "Idle"
end

-- ─────────────────────────────────────────────
-- Main regen loop
-- ─────────────────────────────────────────────

task.spawn(function()
    while true do
        local now = tick()

        for _, player in ipairs(Players:GetPlayers()) do
            local userId   = player.UserId
            local regenData = ElementState.GetRegenData(player)
            if not regenData then
                task.wait(TICK_RATE)
                continue
            end

            local chakra = regenData.chakra

            -- Skip if already full
            if chakra >= MAX_CHAKRA then
                continue
            end

            -- Hit pause — took damage recently
            if now < regenData.regenPausedUntil then
                dbg(player.Name, "regen paused — hit recently")
                continue
            end

            -- Post-technique pause — used a technique recently
            if (now - regenData.techniqueUsedAt) < POST_USE_PAUSE then
                dbg(player.Name, "regen paused — technique used recently")
                continue
            end

            -- Determine rate from current state
            local rate, stateName = getRegenRate(player)

            if rate <= 0 then
                dbg(player.Name, "regen suppressed —", stateName)
                continue
            end

            -- Apply regen tick
            local gained   = rate * REGEN_PER_TICK
            local newChakra = math.min(chakra + gained, MAX_CHAKRA)
            ElementState.SetChakraSilent(player, newChakra)

            dbg(player.Name, "regen tick |", stateName, "| +" .. string.format("%.2f", gained), "→", string.format("%.1f", newChakra))

            -- Throttled push to client
            local lastPush = lastPushAt[userId] or 0
            if now - lastPush >= PUSH_INTERVAL then
                ElementState.PushToClient(player)
                lastPushAt[userId] = now
            end
        end

        task.wait(TICK_RATE)
    end
end)

-- Clean up throttle table on player leave
Players.PlayerRemoving:Connect(function(player)
    lastPushAt[player.UserId] = nil
end)

print("✅ ElementRegenerator initialized")