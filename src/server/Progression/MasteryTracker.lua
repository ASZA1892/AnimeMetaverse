-- src/server/Progression/MasteryTracker.lua
-- Owns per-technique mastery point accumulation and tier advancement.
-- Called by CombatHandler and ElementHandler after confirmed hits.
-- Fires ProgressionRemote "MASTERY_UPDATE" to client on tier change.
-- DataStore persistence deferred to Phase 3.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function safeWait(parent, name, timeout)
    if not parent then
        warn(("[MasteryTracker] safeWait: parent is nil for '%s'"):format(name))
        return nil
    end
    local ok, inst = pcall(function()
        return parent:WaitForChild(name, timeout)
    end)
    if not ok then
        warn(("[MasteryTracker] safeWait: WaitForChild('%s') errored"):format(name))
        return nil
    end
    if not inst then
        warn(("[MasteryTracker] safeWait: WaitForChild('%s') timed out"):format(name))
        return nil
    end
    return inst
end

local function safeRequire(inst, name)
    if not inst then
        warn(("[MasteryTracker] safeRequire: %s is nil"):format(name))
        return nil
    end
    local className = (inst.ClassName and tostring(inst.ClassName)) or "no ClassName"
    print(("DEBUG: safeRequire target %s -> ClassName=%s typeof=%s"):format(name, className, typeof(inst)))
    if className ~= "ModuleScript" then
        warn(("[MasteryTracker] safeRequire: %s is not a ModuleScript (ClassName=%s)"):format(name, className))
    end
    local ok, result = pcall(require, inst)
    if not ok then
        warn(("[MasteryTracker] safeRequire: require(%s) failed: %s"):format(name, tostring(result)))
        return nil
    end
    return result
end

local sharedFolder      = safeWait(ReplicatedStorage, "Shared",           10)
local typesFolder       = safeWait(sharedFolder,      "Types",            10)
local constantsModule   = safeWait(typesFolder,       "constants",         5)
local progressionModule = safeWait(sharedFolder,      "ProgressionState",  5)

print("DEBUG: module presence:",
    "Shared=",           tostring(sharedFolder ~= nil),
    "Types=",            tostring(typesFolder ~= nil),
    "constants=",        tostring(constantsModule ~= nil),
    "ProgressionState=", tostring(progressionModule ~= nil)
)

local Constants        = safeRequire(constantsModule,   "constants")
local ProgressionState = safeRequire(progressionModule, "ProgressionState")

if not Constants then
    error("[MasteryTracker] Constants failed to load")
end
if not ProgressionState then
    error("[MasteryTracker] ProgressionState failed to load")
end

local function dbg(...)
    if Constants.DEBUG then
        print("[MasteryTracker]", ...)
    end
end

local MasteryTracker = {}

-- ─────────────────────────────────────────────
-- TIER DEFINITIONS
-- Points required to advance FROM this tier to the next.
-- Tier 5 (Final/Resonance) has no cap — resonance is infinite.
-- ─────────────────────────────────────────────

local TIER_NAMES = {
    [1] = "Raw",
    [2] = "Refined",
    [3] = "Mastered",
    [4] = "Transcendent",
    [5] = "Final",
}

local TIER_THRESHOLDS = {
    [1] = 100,   -- Raw       → Refined       (100 points)
    [2] = 300,   -- Refined   → Mastered      (300 points)
    [3] = 700,   -- Mastered  → Transcendent  (700 points)
    [4] = 1500,  -- Transcendent → Final      (1500 points)
    [5] = nil,   -- Final: no cap, resonance accumulates infinitely
}

-- Points awarded per hit by hit context
local POINTS_PER_HIT        = 1    -- standard hit with this technique
local POINTS_VITAL_NODE_HIT = 5    -- hitting a Vital 5 node with this technique
local POINTS_UNDERDOG_BONUS = 3    -- extra points when attacker GPL < target GPL * 0.75

-- Affinity bonus: if technique element matches player affinity, multiply points by this
local AFFINITY_MULTIPLIER = 2.0

-- ─────────────────────────────────────────────
-- ProgressionRemote for tier-up notifications
-- ─────────────────────────────────────────────

local ProgressionRemote = ReplicatedStorage:FindFirstChild("ProgressionRemote")
if not ProgressionRemote then
    ProgressionRemote = ReplicatedStorage:WaitForChild("ProgressionRemote", 10)
end

local function notifyTierUp(player, techniqueId, newTier)
    if not ProgressionRemote then return end
    if not (typeof(player) == "Instance" and player:IsA("Player")) then return end
    ProgressionRemote:FireClient(player, "TIER_UP", {
        techniqueId = techniqueId,
        newTier     = newTier,
        tierName    = TIER_NAMES[newTier] or "Unknown",
    })
    dbg(player.Name, techniqueId, "→ tier up to", TIER_NAMES[newTier] or newTier)
end

-- ─────────────────────────────────────────────
-- INTERNAL: attempt tier advancement
-- Returns new tier if advanced, nil if not.
-- ─────────────────────────────────────────────

local function tryAdvanceTier(player, techniqueId, masteryEntry)
    local currentTier = masteryEntry.tier
    if currentTier >= 5 then
        -- At Final tier — accumulate resonance instead
        return nil
    end

    local threshold = TIER_THRESHOLDS[currentTier]
    if not threshold then return nil end

    if masteryEntry.points >= threshold then
        local newTier = currentTier + 1
        masteryEntry.points = masteryEntry.points - threshold  -- carry over excess
        ProgressionState.SetMasteryTier(player, techniqueId, newTier)
        notifyTierUp(player, techniqueId, newTier)
        return newTier
    end

    return nil
end

-- ─────────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────────

-- Called after a confirmed hit with a technique or physical move.
-- context = {
--     player       = Player,       -- attacker
--     techniqueId  = string,       -- technique or move id
--     element      = string|nil,   -- technique element (nil for physical)
--     hitVitalNode = bool,         -- true if a Vital 5 node was hit
--     targetGPL    = number|nil,   -- for underdog bonus calculation
--     attackerGPL  = number|nil,   -- for underdog bonus calculation
-- }
function MasteryTracker.RegisterHit(context)
    if type(context) ~= "table" then return end

    local player      = context.player
    local techniqueId = context.techniqueId

    if not (typeof(player) == "Instance" and player:IsA("Player")) then return end
    if type(techniqueId) ~= "string" or techniqueId == "" then return end

    -- Ensure mastery entry exists
    ProgressionState.InitMastery(player, techniqueId)

    local masteryEntry = ProgressionState.GetMastery(player, techniqueId)
    if not masteryEntry then
        dbg("GetMastery returned nil for", player.Name, techniqueId)
        return
    end

    -- At Final tier, skip points and go straight to resonance
    if masteryEntry.tier >= 5 then
        local resonanceGain = 1
        if context.hitVitalNode then resonanceGain = resonanceGain + 2 end
        ProgressionState.AddResonance(player, techniqueId, resonanceGain)
        dbg(player.Name, techniqueId, "resonance +", resonanceGain, "→", masteryEntry.resonance + resonanceGain)
        return
    end

    -- Base points for the hit
    local points = POINTS_PER_HIT

    -- Vital node bonus
    if context.hitVitalNode then
        points = points + POINTS_VITAL_NODE_HIT
        dbg(player.Name, techniqueId, "vital node bonus +", POINTS_VITAL_NODE_HIT)
    end

    -- Underdog bonus: attacker GPL significantly below target GPL
    local attackerGPL = tonumber(context.attackerGPL) or 0
    local targetGPL   = tonumber(context.targetGPL)   or 0
    if targetGPL > 0 and attackerGPL < targetGPL * 0.75 then
        points = points + POINTS_UNDERDOG_BONUS
        dbg(player.Name, techniqueId, "underdog bonus +", POINTS_UNDERDOG_BONUS)
    end

    -- Affinity multiplier: technique element matches player affinity
    -- ElementState is not required here to keep this module lean.
    -- The caller can pass affinityMatch = true in context if they know it.
    if context.affinityMatch == true then
        points = math.floor(points * AFFINITY_MULTIPLIER)
        dbg(player.Name, techniqueId, "affinity multiplier x", AFFINITY_MULTIPLIER, "→", points)
    end

    -- Add points
    ProgressionState.AddMasteryPoints(player, techniqueId, points)
    dbg(player.Name, techniqueId, "mastery +" .. points,
        "| tier", masteryEntry.tier, "| points", masteryEntry.points + points)

    -- Re-fetch entry after add (AddMasteryPoints mutates via ProgressionState)
    local updated = ProgressionState.GetMastery(player, techniqueId)
    if updated then
        tryAdvanceTier(player, techniqueId, updated)
    end
end

-- Directly query mastery tier for a player and technique.
-- Used by ElementHandler and CombatHandler to determine which tier data to use.
function MasteryTracker.GetTier(player, techniqueId)
    if not (typeof(player) == "Instance" and player:IsA("Player")) then return 1 end
    if type(techniqueId) ~= "string" then return 1 end
    local entry = ProgressionState.GetMastery(player, techniqueId)
    return entry and entry.tier or 1
end

-- Returns the string tier name for a player and technique.
function MasteryTracker.GetTierName(player, techniqueId)
    local tier = MasteryTracker.GetTier(player, techniqueId)
    return TIER_NAMES[tier] or "Raw"
end

-- Returns resonance points for a technique at Final tier.
function MasteryTracker.GetResonance(player, techniqueId)
    if not (typeof(player) == "Instance" and player:IsA("Player")) then return 0 end
    local entry = ProgressionState.GetMastery(player, techniqueId)
    return entry and entry.resonance or 0
end

-- ─────────────────────────────────────────────
-- SELF TEST
-- ─────────────────────────────────────────────

if Constants.DEBUG then
    task.spawn(function()
        task.wait(3)

        -- Test 1: GetTier returns 1 for unknown player/technique (defaults)
        local tier = MasteryTracker.GetTier(nil, "fake_technique")
        assert(tier == 1, "nil player should default to tier 1")

        -- Test 2: GetTierName returns "Raw" for tier 1
        local name = TIER_NAMES[1]
        assert(name == "Raw", "tier 1 should be Raw")

        -- Test 3: TIER_THRESHOLDS monotonically increasing
        local prev = 0
        for i = 1, 4 do
            local t = TIER_THRESHOLDS[i]
            assert(t > prev, ("threshold %d should be > threshold %d"):format(i, i-1))
            prev = t
        end
        assert(TIER_THRESHOLDS[5] == nil, "Final tier should have no threshold")

        -- Test 4: points accumulate correctly (simulate without real player)
        -- Just verify the constants are sane
        assert(POINTS_PER_HIT > 0,        "POINTS_PER_HIT must be positive")
        assert(POINTS_VITAL_NODE_HIT > 0,  "POINTS_VITAL_NODE_HIT must be positive")
        assert(POINTS_UNDERDOG_BONUS >= 0, "POINTS_UNDERDOG_BONUS must be non-negative")
        assert(AFFINITY_MULTIPLIER >= 1.0, "AFFINITY_MULTIPLIER must be >= 1.0")

        print("[MasteryTracker self-test] PASSED")
    end)
end

print("✅ MasteryTracker initialized")

return MasteryTracker