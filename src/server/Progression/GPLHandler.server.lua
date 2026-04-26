-- src/server/Progression/GPLHandler.server.lua
-- Authoritative Greatest Player Level handler.
-- Owns all GPL gain (kills) and loss (deaths) calculations.
-- Implements layered death penalty with session cap and underdog protection.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─────────────────────────────────────────────
-- SAFE LOADERS
-- ─────────────────────────────────────────────

local function safeWait(parent, name, timeout)
    if not parent then
        warn(("[GPLHandler] safeWait: parent is nil for '%s'"):format(name))
        return nil
    end
    local ok, inst = pcall(function()
        return parent:WaitForChild(name, timeout)
    end)
    if not ok then
        warn(("[GPLHandler] safeWait: WaitForChild('%s') errored"):format(name))
        return nil
    end
    if not inst then
        warn(("[GPLHandler] safeWait: WaitForChild('%s') timed out"):format(name))
        return nil
    end
    return inst
end

local function safeRequire(inst, name)
    if not inst then
        warn(("[GPLHandler] safeRequire: %s is nil"):format(name))
        return nil
    end
    local className = (inst.ClassName and tostring(inst.ClassName)) or "no ClassName"
    print(("DEBUG: safeRequire target %s -> ClassName=%s typeof=%s"):format(name, className, typeof(inst)))
    if className ~= "ModuleScript" then
        warn(("[GPLHandler] safeRequire: %s is not a ModuleScript (ClassName=%s)"):format(name, className))
    end
    local ok, result = pcall(require, inst)
    if not ok then
        warn(("[GPLHandler] safeRequire: require(%s) failed: %s"):format(name, tostring(result)))
        return nil
    end
    return result
end

local sharedFolder       = safeWait(ReplicatedStorage, "Shared", 10)
local typesFolder        = safeWait(sharedFolder,      "Types",  10)
local constantsModule    = safeWait(typesFolder,       "constants",        5)
local progressionModule  = safeWait(sharedFolder,      "ProgressionState", 5)

print("DEBUG: module presence:",
    "Shared=",           tostring(sharedFolder ~= nil),
    "Types=",            tostring(typesFolder ~= nil),
    "constants=",        tostring(constantsModule ~= nil),
    "ProgressionState=", tostring(progressionModule ~= nil)
)

local Constants        = safeRequire(constantsModule,   "constants")
local ProgressionState = safeRequire(progressionModule, "ProgressionState")

if not Constants then
    error("[GPLHandler] Constants failed to load")
end
if not ProgressionState then
    error("[GPLHandler] ProgressionState failed to load")
end

local function dbg(...)
    if Constants.DEBUG then
        print("[GPLHandler]", ...)
    end
end

-- ─────────────────────────────────────────────
-- TUNING CONSTANTS
-- All numbers are intentionally exposed so tuning happens in one place.
-- ─────────────────────────────────────────────

-- Death penalty layers
local BASE_LOSS_PERCENT      = 0.04   -- baseline loss = 4% of attacker's GPL
local FLOOR_LOSS             = 2      -- minimum points lost on any death (prevents 0 at low GPL)
local MAX_SESSION_LOSS_RATIO = Constants.GPL_MAX_SESSION_LOSS or 0.10
local MAX_TOTAL_LOSS_RATIO   = Constants.GPL_MAX_LOSS_PERCENT  or 0.05

-- Skill gap multiplier — modifies LOSS for victim based on attacker GPL vs victim GPL
-- gap = (victimGPL - attackerGPL) / victimGPL
-- gap > 0 means attacker is below victim (underdog kill) → victim loses MORE
-- gap < 0 means attacker is above victim (stronger kill) → victim loses LESS
local UNDERDOG_LOSS_MULT_MAX = 1.75   -- max loss multiplier when attacker is far weaker
local PRO_KILL_LOSS_MULT_MIN = 0.50   -- min loss multiplier when attacker is far stronger

-- GPL gain calculation for the attacker — mirror of loss with different scaling
local BASE_GAIN_PERCENT      = 0.05   -- baseline gain = 5% of victim's GPL
local FLOOR_GAIN             = 2      -- minimum points gained on any kill
local UNDERDOG_GAIN_MULT_MAX = 2.00   -- max gain multiplier when attacker is far weaker
local PRO_KILL_GAIN_MULT_MIN = 0.30   -- min gain multiplier when attacker is far stronger

-- Skill gap clamp range — gap is clamped to this range before scaling
local GAP_CLAMP = 0.6   -- a 60% GPL difference is treated as the maximum meaningful gap

-- ─────────────────────────────────────────────
-- HELPERS
-- ─────────────────────────────────────────────

local function clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

-- Map a clamped skill gap [-GAP_CLAMP, +GAP_CLAMP] onto a multiplier [minMult, maxMult].
-- gap = 0  → multiplier = 1.0 (no scaling)
-- gap = +GAP_CLAMP → multiplier = maxMult (attacker weaker, larger swing)
-- gap = -GAP_CLAMP → multiplier = minMult (attacker stronger, smaller swing)
local function gapToMultiplier(gap, minMult, maxMult)
    local clamped = clamp(gap, -GAP_CLAMP, GAP_CLAMP)
    if clamped >= 0 then
        local t = clamped / GAP_CLAMP
        return 1 + (maxMult - 1) * t
    else
        local t = -clamped / GAP_CLAMP
        return 1 - (1 - minMult) * t
    end
end

-- Compute skill gap from attacker and victim GPL.
-- Returns 0 if victimGPL <= 0 (avoid division by zero).
local function computeGap(attackerGPL, victimGPL)
    if victimGPL <= 0 then return 0 end
    return (victimGPL - attackerGPL) / victimGPL
end

-- ─────────────────────────────────────────────
-- LOSS CALCULATION (victim's perspective)
-- ─────────────────────────────────────────────

-- Calculates how many GPL points the victim should lose based on:
--   1. Base layer: percentage of victim's GPL
--   2. Skill gap layer: attacker weaker → bigger loss; attacker stronger → smaller loss
--   3. Floor: minimum loss
--   4. Total loss cap: never lose more than MAX_TOTAL_LOSS_RATIO of current GPL
--   5. Session gain cap: never lose more than MAX_SESSION_LOSS_RATIO of session gains
function GPLHandler_CalculateLoss(attackerGPL, victimGPL, sessionGained)
    -- Validate
    attackerGPL    = math.max(0, tonumber(attackerGPL) or 0)
    victimGPL      = math.max(0, tonumber(victimGPL) or 0)
    sessionGained  = math.max(0, tonumber(sessionGained) or 0)

    if victimGPL <= 0 then
        return 0, "victim has 0 GPL"
    end

    -- Layer 1: base loss
    local baseLoss = victimGPL * BASE_LOSS_PERCENT

    -- Layer 2: skill gap multiplier (loss scales)
    local gap     = computeGap(attackerGPL, victimGPL)
    local gapMult = gapToMultiplier(gap, PRO_KILL_LOSS_MULT_MIN, UNDERDOG_LOSS_MULT_MAX)
    local scaledLoss = baseLoss * gapMult

    -- Layer 3: floor — at least FLOOR_LOSS unless capped below
    local flooredLoss = math.max(scaledLoss, FLOOR_LOSS)

    -- Layer 4: total loss cap — never lose more than MAX_TOTAL_LOSS_RATIO of current GPL
    local totalCap = victimGPL * MAX_TOTAL_LOSS_RATIO

    -- Layer 5: session loss cap — never lose more than MAX_SESSION_LOSS_RATIO of session gains
    -- This only kicks in when sessionGained > 0; if 0, this cap is bypassed
    local sessionCap = math.huge
    if sessionGained > 0 then
        sessionCap = sessionGained * MAX_SESSION_LOSS_RATIO
    end

    -- Final loss = min of all caps
    local finalLoss = math.min(flooredLoss, totalCap, sessionCap)

    -- Floor the result (GPL is integer)
    finalLoss = math.floor(finalLoss + 0.5)

    -- Sanity: never below 0, never above victim GPL
    finalLoss = math.max(0, math.min(finalLoss, victimGPL))

    local reason = string.format(
        "base=%.2f gap=%.3f mult=%.3f scaled=%.2f floored=%.2f totalCap=%.2f sessionCap=%s final=%d",
        baseLoss, gap, gapMult, scaledLoss, flooredLoss, totalCap,
        sessionGained > 0 and string.format("%.2f", sessionCap) or "n/a",
        finalLoss
    )

    return finalLoss, reason
end

-- ─────────────────────────────────────────────
-- GAIN CALCULATION (attacker's perspective)
-- ─────────────────────────────────────────────

-- Calculates how many GPL points the attacker should gain based on:
--   1. Base layer: percentage of victim's GPL
--   2. Skill gap layer: attacker weaker → bigger gain; attacker stronger → smaller gain
--   3. Floor: minimum gain
function GPLHandler_CalculateGain(attackerGPL, victimGPL)
    attackerGPL = math.max(0, tonumber(attackerGPL) or 0)
    victimGPL   = math.max(0, tonumber(victimGPL) or 0)

    if victimGPL <= 0 then
        -- Killing a 0-GPL target is worthless
        return 0, "victim has 0 GPL"
    end

    local baseGain = victimGPL * BASE_GAIN_PERCENT

    local gap     = computeGap(attackerGPL, victimGPL)
    local gapMult = gapToMultiplier(gap, PRO_KILL_GAIN_MULT_MIN, UNDERDOG_GAIN_MULT_MAX)
    local scaledGain = baseGain * gapMult

    local flooredGain = math.max(scaledGain, FLOOR_GAIN)

    local finalGain = math.floor(flooredGain + 0.5)
    finalGain = math.max(0, finalGain)

    local reason = string.format(
        "base=%.2f gap=%.3f mult=%.3f scaled=%.2f floored=%.2f final=%d",
        baseGain, gap, gapMult, scaledGain, flooredGain, finalGain
    )

    return finalGain, reason
end

-- ─────────────────────────────────────────────
-- PUBLIC API — APPLY KILL/DEATH TO PLAYERS
-- ─────────────────────────────────────────────

local GPLHandler = {}

-- Expose the pure calculators so other systems (UI previews, anti-cheat, tests) can use them.
GPLHandler.CalculateLoss = GPLHandler_CalculateLoss
GPLHandler.CalculateGain = GPLHandler_CalculateGain

-- Apply a kill: attacker gains, victim loses. Both are clamped per the rules above.
-- Returns a result table for logging / UI feedback.
function GPLHandler.ApplyKill(attacker, victim)
    -- Validate players
    if not (typeof(attacker) == "Instance" and attacker:IsA("Player")) then
        return { success = false, reason = "attacker invalid" }
    end
    if not (typeof(victim) == "Instance" and victim:IsA("Player")) then
        return { success = false, reason = "victim invalid" }
    end
    if attacker == victim then
        return { success = false, reason = "self kill — no GPL change" }
    end

    local attackerGPL   = ProgressionState.GetGPL(attacker)
    local victimGPL     = ProgressionState.GetGPL(victim)
    local sessionGained = ProgressionState.GetSessionGPLGained(victim)

    local gain, gainReason = GPLHandler.CalculateGain(attackerGPL, victimGPL)
    local loss, lossReason = GPLHandler.CalculateLoss(attackerGPL, victimGPL, sessionGained)

    -- Apply
    if gain > 0 then
        ProgressionState.AddGPL(attacker, gain)
    end
    if loss > 0 then
        ProgressionState.DeductGPL(victim, loss)
    end

    dbg(("ApplyKill | %s (GPL %d) killed %s (GPL %d) | session=%d | +%d / -%d"):format(
        attacker.Name, attackerGPL, victim.Name, victimGPL, sessionGained, gain, loss
    ))
    dbg("  gain breakdown:", gainReason)
    dbg("  loss breakdown:", lossReason)

    return {
        success      = true,
        attacker     = attacker,
        victim       = victim,
        attackerGPL  = attackerGPL,
        victimGPL    = victimGPL,
        gainApplied  = gain,
        lossApplied  = loss,
        gainReason   = gainReason,
        lossReason   = lossReason,
    }
end

-- Apply a death without a known killer (environmental, suicide, fall, etc).
-- Uses the victim's own GPL for the gap calc → no underdog bonus to anyone.
-- The loss is calculated as if attacker == victim, which gives gap = 0 → multiplier = 1.0
function GPLHandler.ApplyDeath(victim)
    if not (typeof(victim) == "Instance" and victim:IsA("Player")) then
        return { success = false, reason = "victim invalid" }
    end

    local victimGPL     = ProgressionState.GetGPL(victim)
    local sessionGained = ProgressionState.GetSessionGPLGained(victim)
    local loss, reason  = GPLHandler.CalculateLoss(victimGPL, victimGPL, sessionGained)

    if loss > 0 then
        ProgressionState.DeductGPL(victim, loss)
    end

    dbg(("ApplyDeath | %s (GPL %d) died with no killer | -%d"):format(
        victim.Name, victimGPL, loss
    ))
    dbg("  loss breakdown:", reason)

    return {
        success     = true,
        victim      = victim,
        victimGPL   = victimGPL,
        lossApplied = loss,
        lossReason  = reason,
    }
end

-- ─────────────────────────────────────────────
-- TRACK KILLS — listen to Humanoid.Died and resolve attacker
-- ─────────────────────────────────────────────

-- We track who last damaged each player so we can credit the kill correctly.
-- Kept simple: last attacker wins. Phase 3 may add assist tracking.
local lastAttacker = setmetatable({}, { __mode = "k" })  -- victim Player → attacker Player

-- Public hook for combat handlers to call when they damage a player.
-- This is wired into CombatHandler / ElementHandler in a follow-up edit.
function GPLHandler.RegisterDamage(attacker, victim)
    if not (typeof(attacker) == "Instance" and attacker:IsA("Player")) then return end
    if not (typeof(victim)   == "Instance" and victim:IsA("Player"))   then return end
    if attacker == victim then return end
    lastAttacker[victim] = attacker
end

local function onCharacterAdded(player, character)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if not humanoid then return end

    humanoid.Died:Connect(function()
        local attacker = lastAttacker[player]
        lastAttacker[player] = nil

        if attacker and attacker.Parent == Players then
            GPLHandler.ApplyKill(attacker, player)
        else
            GPLHandler.ApplyDeath(player)
        end
    end)
end

local function onPlayerAdded(player)
    if player.Character then
        onCharacterAdded(player, player.Character)
    end
    player.CharacterAdded:Connect(function(character)
        onCharacterAdded(player, character)
    end)
end

for _, player in ipairs(Players:GetPlayers()) do
    onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
    lastAttacker[player] = nil
end)

-- ─────────────────────────────────────────────
-- SELF-TEST
-- Verifies the formula behaves correctly under representative scenarios.
-- ─────────────────────────────────────────────

if Constants.DEBUG then
    task.spawn(function()
        task.wait(3)

        -- Scenario 1: equal GPL, fresh session (no session gains)
        local lossA = GPLHandler.CalculateLoss(100, 100, 0)
        assert(lossA >= FLOOR_LOSS, "equal GPL loss should hit floor or higher")
        dbg(string.format("[self-test] equal GPL loss=%d (expected >= %d)", lossA, FLOOR_LOSS))

        -- Scenario 2: underdog kill (attacker 30 vs victim 100) — victim loses more
        local lossUnderdog = GPLHandler.CalculateLoss(30, 100, 0)
        assert(lossUnderdog > lossA, "underdog kill should make victim lose more than equal-GPL")
        dbg(string.format("[self-test] underdog loss=%d > equal=%d ✓", lossUnderdog, lossA))

        -- Scenario 3: pro kill (attacker 200 vs victim 100) — victim loses less
        local lossProKill = GPLHandler.CalculateLoss(200, 100, 0)
        assert(lossProKill <= lossA, "pro kill should reduce victim loss vs equal")
        dbg(string.format("[self-test] pro-kill loss=%d <= equal=%d ✓", lossProKill, lossA))

        -- Scenario 4: session cap kicks in
        -- Victim with 1000 GPL killed equal-tier with only 50 session gain
        -- Loss without cap = 1000 * 0.04 = 40, but session cap = 50 * 0.10 = 5 → final = 5
        local lossCapped = GPLHandler.CalculateLoss(1000, 1000, 50)
        assert(lossCapped <= 5, ("session cap should clamp loss to ~5, got %d"):format(lossCapped))
        dbg(string.format("[self-test] session-capped loss=%d (expected <= 5) ✓", lossCapped))

        -- Scenario 5: total cap — even high session gains shouldn't let you lose >5% of GPL
        local lossTotalCap = GPLHandler.CalculateLoss(1000, 1000, 99999)
        local maxAllowed   = 1000 * MAX_TOTAL_LOSS_RATIO
        assert(lossTotalCap <= maxAllowed, ("total cap exceeded: %d > %d"):format(lossTotalCap, maxAllowed))
        dbg(string.format("[self-test] total-capped loss=%d <= %.0f ✓", lossTotalCap, maxAllowed))

        -- Scenario 6: gain calculations
        local gainEqual    = GPLHandler.CalculateGain(100, 100)
        local gainUnderdog = GPLHandler.CalculateGain(30, 100)
        local gainProKill  = GPLHandler.CalculateGain(200, 100)
        assert(gainUnderdog > gainEqual, "underdog should gain more than equal")
        assert(gainProKill  < gainEqual, "pro-kill should gain less than equal")
        dbg(string.format("[self-test] gains: underdog=%d > equal=%d > pro-kill=%d ✓",
            gainUnderdog, gainEqual, gainProKill))

        -- Scenario 7: 0 GPL victim → 0 gain, 0 loss
        local gainZero = GPLHandler.CalculateGain(100, 0)
        local lossZero = GPLHandler.CalculateLoss(100, 0, 0)
        assert(gainZero == 0, "killing 0-GPL victim gives 0 gain")
        assert(lossZero == 0, "0-GPL victim loses 0")
        dbg("[self-test] zero-GPL victim handled ✓")

        -- Scenario 8: monotonicity — losses should not exceed victim's GPL
        local lossEverything = GPLHandler.CalculateLoss(0, 10, 0)
        assert(lossEverything <= 10, "cannot lose more than victim has")
        dbg(string.format("[self-test] tiny-victim loss=%d <= 10 ✓", lossEverything))

        print("[GPLHandler self-test] PASSED")
    end)
end

print("✅ GPLHandler initialized")

return GPLHandler