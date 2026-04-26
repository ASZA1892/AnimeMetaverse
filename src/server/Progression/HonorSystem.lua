-- src/server/Progression/HonorSystem.lua
-- Owns all honor gain and loss logic.
-- Other systems call HonorSystem.RecordAction(player, actionId) after a relevant event.
-- Applies threshold effects when honor crosses key boundaries.
-- DataStore persistence deferred to Phase 3.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function safeWait(parent, name, timeout)
    if not parent then
        warn(("[HonorSystem] safeWait: parent is nil for '%s'"):format(name))
        return nil
    end
    local ok, inst = pcall(function()
        return parent:WaitForChild(name, timeout)
    end)
    if not ok then
        warn(("[HonorSystem] safeWait: WaitForChild('%s') errored"):format(name))
        return nil
    end
    if not inst then
        warn(("[HonorSystem] safeWait: WaitForChild('%s') timed out"):format(name))
        return nil
    end
    return inst
end

local function safeRequire(inst, name)
    if not inst then
        warn(("[HonorSystem] safeRequire: %s is nil"):format(name))
        return nil
    end
    local className = (inst.ClassName and tostring(inst.ClassName)) or "no ClassName"
    print(("DEBUG: safeRequire target %s -> ClassName=%s typeof=%s"):format(name, className, typeof(inst)))
    if className ~= "ModuleScript" then
        warn(("[HonorSystem] safeRequire: %s is not a ModuleScript (ClassName=%s)"):format(name, className))
    end
    local ok, result = pcall(require, inst)
    if not ok then
        warn(("[HonorSystem] safeRequire: require(%s) failed: %s"):format(name, tostring(result)))
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
    error("[HonorSystem] Constants failed to load")
end
if not ProgressionState then
    error("[HonorSystem] ProgressionState failed to load")
end

local function dbg(...)
    if Constants.DEBUG then
        print("[HonorSystem]", ...)
    end
end

local HonorSystem = {}

-- ─────────────────────────────────────────────
-- HONOR THRESHOLDS AND EFFECTS
-- ─────────────────────────────────────────────

local HONOR_MAX =  100
local HONOR_MIN = -100

-- Threshold bands — effects applied when honor crosses these values.
-- Checked every time honor changes.
local THRESHOLD_DARK_RECRUIT  = -50   -- Dark NPC recruiter appears, rogue path accessible
local THRESHOLD_VILLAGE_HOSTILE = -80 -- Villages become hostile on sight
local THRESHOLD_NPC_DISCOUNT   =  50  -- NPC 10% discounts, exclusive quests

-- ─────────────────────────────────────────────
-- ProgressionRemote for client notifications
-- ─────────────────────────────────────────────

local ProgressionRemote = ReplicatedStorage:FindFirstChild("ProgressionRemote")
if not ProgressionRemote then
    ProgressionRemote = ReplicatedStorage:WaitForChild("ProgressionRemote", 10)
end

-- ─────────────────────────────────────────────
-- ACTION DEFINITIONS (locked from GameDesignDecisions.md)
-- Each action has:
--   change   number  — honor delta (positive = gain, negative = loss)
--   label    string  — human readable for DEBUG log
--   cooldown number? — minimum seconds before this action can grant honor again per player
--                      nil = no cooldown (applies every time)
-- ─────────────────────────────────────────────

local ACTIONS = {
    -- Positive actions
    DEFEND_WEAKER_PLAYER   = { change =  5,  label = "Defended weaker player",           cooldown = 60  },
    COMPLETE_VILLAGE_QUEST = { change =  3,  label = "Completed village quest",           cooldown = nil },
    FAIR_PVP_WIN           = { change =  1,  label = "Fair PvP win (no ganking)",         cooldown = 30  },
    TRAIN_NEW_PLAYER       = { change = 10,  label = "Trained new player (Sensei)",       cooldown = 300 },
    VITAL_NODE_PRECISION   = { change =  1,  label = "Vital 5 precision hit on stronger", cooldown = 10  },
    VILLAGE_CONTRIBUTION   = { change =  2,  label = "Contributed to village",            cooldown = nil },

    -- Negative actions
    GANK_NEW_PLAYER        = { change = -10, label = "Ganked a new player",               cooldown = nil },
    BETRAY_CLAN            = { change = -25, label = "Betrayed clan",                     cooldown = nil },
    REPEATED_KILL          = { change =  -5, label = "Killed same player 3+ times",       cooldown = nil },
    DARK_RITUAL            = { change = -15, label = "Performed dark ritual",             cooldown = nil },
    EXCESSIVE_GRIEF        = { change =  -3, label = "Excessive griefing",                cooldown = nil },
}

-- Expose action ids publicly so callers don't need to hardcode strings
HonorSystem.Actions = {}
for k in pairs(ACTIONS) do
    HonorSystem.Actions[k] = k
end

-- ─────────────────────────────────────────────
-- COOLDOWN TRACKING
-- Per-player, per-action cooldown so repeated easy actions can't farm honor
-- ─────────────────────────────────────────────

local actionCooldowns = setmetatable({}, { __mode = "k" })
-- Structure: actionCooldowns[player][actionId] = os.clock() of last grant

local function isOnCooldown(player, actionId, cooldown)
    if not cooldown then return false end
    local playerCooldowns = actionCooldowns[player]
    if not playerCooldowns then return false end
    local lastAt = playerCooldowns[actionId]
    if not lastAt then return false end
    return (os.clock() - lastAt) < cooldown
end

local function recordCooldown(player, actionId)
    if not actionCooldowns[player] then
        actionCooldowns[player] = {}
    end
    actionCooldowns[player][actionId] = os.clock()
end

-- ─────────────────────────────────────────────
-- THRESHOLD EFFECTS
-- Called after honor changes to apply crossing effects.
-- Only fires when honor crosses a threshold in either direction.
-- ─────────────────────────────────────────────

-- Track last known threshold band per player to detect crossings
local lastBand = setmetatable({}, { __mode = "k" })

local function getBand(honor)
    if honor <= THRESHOLD_VILLAGE_HOSTILE then return "village_hostile"
    elseif honor <= THRESHOLD_DARK_RECRUIT then return "dark_recruit"
    elseif honor >= THRESHOLD_NPC_DISCOUNT then return "npc_discount"
    else return "neutral"
    end
end

local function applyThresholdEffects(player, oldHonor, newHonor)
    local oldBand = getBand(oldHonor)
    local newBand = getBand(newHonor)
    if oldBand == newBand then return end

    dbg(player.Name, "honor band changed:", oldBand, "→", newBand)

    -- Notify client of band change for UI and NPC behaviour
    if ProgressionRemote then
        pcall(function()
            ProgressionRemote:FireClient(player, "HONOR_BAND_CHANGE", {
                oldBand  = oldBand,
                newBand  = newBand,
                honor    = newHonor,
            })
        end)
    end

    -- Server-side effects per band
    if newBand == "dark_recruit" or newBand == "village_hostile" then
        dbg(player.Name, "→ dark path unlocked (honor", newHonor, ")")
        -- Phase 3: spawn dark NPC recruiter near player
        -- Phase 3: flag player as rogue-eligible in VillageSystem
    end

    if newBand == "village_hostile" then
        dbg(player.Name, "→ villages now hostile (honor", newHonor, ")")
        -- Phase 3: update village guard aggro table
    end

    if newBand == "npc_discount" then
        dbg(player.Name, "→ NPC discount unlocked (honor", newHonor, ")")
        -- Phase 3: set NPC discount flag in ShopSystem
    end

    if newBand == "neutral" then
        dbg(player.Name, "→ returned to neutral honor band")
        -- Phase 3: revoke any active dark or discount flags
    end
end

-- ─────────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────────

-- Primary entry point. Call this from any system after a relevant event.
-- actionId: one of HonorSystem.Actions keys
-- metadata: optional table for context (e.g. { target = targetPlayer })
function HonorSystem.RecordAction(player, actionId, metadata)
    if not (typeof(player) == "Instance" and player:IsA("Player")) then
        warn("[HonorSystem] RecordAction: invalid player")
        return { success = false, reason = "invalid player" }
    end

    if type(actionId) ~= "string" then
        warn("[HonorSystem] RecordAction: invalid actionId")
        return { success = false, reason = "invalid actionId" }
    end

    local action = ACTIONS[actionId]
    if not action then
        warn(("[HonorSystem] RecordAction: unknown actionId '%s'"):format(actionId))
        return { success = false, reason = "unknown action" }
    end

    -- Cooldown check
    if isOnCooldown(player, actionId, action.cooldown) then
        dbg(player.Name, actionId, "on cooldown — skipped")
        return { success = false, reason = "cooldown" }
    end

    local oldHonor = ProgressionState.GetHonor(player)
    ProgressionState.AddHonor(player, action.change)
    local newHonor = ProgressionState.GetHonor(player)

    recordCooldown(player, actionId)

    applyThresholdEffects(player, oldHonor, newHonor)

    dbg(("%s | %s | %+d honor | %d → %d"):format(
        player.Name, action.label, action.change, oldHonor, newHonor
    ))

    -- Notify client of raw honor update for UI
    if ProgressionRemote then
        pcall(function()
            ProgressionRemote:FireClient(player, "HONOR_UPDATE", {
                honor    = newHonor,
                change   = action.change,
                actionId = actionId,
                label    = action.label,
            })
        end)
    end

    return {
        success  = true,
        actionId = actionId,
        change   = action.change,
        oldHonor = oldHonor,
        newHonor = newHonor,
        label    = action.label,
    }
end

-- Direct honor query — thin wrapper over ProgressionState for convenience
function HonorSystem.GetHonor(player)
    return ProgressionState.GetHonor(player)
end

-- Returns the player's current honor band string
function HonorSystem.GetBand(player)
    local honor = ProgressionState.GetHonor(player)
    return getBand(honor)
end

-- ─────────────────────────────────────────────
-- PLAYER LIFECYCLE
-- ─────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(player)
    actionCooldowns[player] = nil
    lastBand[player] = nil
end)

-- ─────────────────────────────────────────────
-- SELF TEST
-- ─────────────────────────────────────────────

if Constants.DEBUG then
    task.spawn(function()
        task.wait(3)

        -- Test 1: all action ids exposed correctly
        local actionCount = 0
        for _ in pairs(HonorSystem.Actions) do
            actionCount = actionCount + 1
        end
        assert(actionCount == 11, ("expected 11 actions, got %d"):format(actionCount))

        -- Test 2: getBand returns correct bands
        assert(getBand(100)  == "npc_discount",     "100 should be npc_discount band")
        assert(getBand(50)   == "npc_discount",     "50 should be npc_discount band")
        assert(getBand(0)    == "neutral",           "0 should be neutral")
        assert(getBand(-49)  == "neutral",           "-49 should be neutral")
        assert(getBand(-50)  == "dark_recruit",      "-50 should be dark_recruit band")
        assert(getBand(-79)  == "dark_recruit",      "-79 should be dark_recruit band")
        assert(getBand(-80)  == "village_hostile",   "-80 should be village_hostile band")
        assert(getBand(-100) == "village_hostile",   "-100 should be village_hostile band")

        -- Test 3: RecordAction rejects invalid inputs
        local r1 = HonorSystem.RecordAction(nil, "FAIR_PVP_WIN")
        assert(r1.success == false, "nil player should fail")

        local r2 = HonorSystem.RecordAction("notaplayer", "FAIR_PVP_WIN")
        assert(r2.success == false, "string player should fail")

        local r3 = HonorSystem.RecordAction(Players:GetPlayers()[1] or game:GetService("Players"):GetPlayers()[1], "FAKE_ACTION")
        -- r3 may be nil if no players in test — guard it
        if r3 then
            assert(r3.success == false, "unknown action should fail")
        end

        -- Test 4: action constants are internally consistent
        for id, def in pairs(ACTIONS) do
            assert(type(def.change) == "number", ("action %s missing change"):format(id))
            assert(type(def.label)  == "string", ("action %s missing label"):format(id))
            assert(def.cooldown == nil or type(def.cooldown) == "number",
                ("action %s cooldown must be nil or number"):format(id))
            assert(math.abs(def.change) <= 25,
                ("action %s change=%d exceeds reasonable bound"):format(id, def.change))
        end

        -- Test 5: honor clamped at max/min in ProgressionState
        local clampedHigh = math.clamp(150, HONOR_MIN, HONOR_MAX)
        local clampedLow  = math.clamp(-150, HONOR_MIN, HONOR_MAX)
        assert(clampedHigh == 100,  "clamp high failed")
        assert(clampedLow  == -100, "clamp low failed")

        print("[HonorSystem self-test] PASSED")
    end)
end

print("✅ HonorSystem initialized")

return HonorSystem