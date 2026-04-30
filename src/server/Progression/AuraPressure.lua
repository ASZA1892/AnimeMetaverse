-- src/server/Progression/AuraPressure.server.lua
-- Power gap prevention system.
-- A high-GPL player attacking a much weaker player drains chakra and stamina faster.
-- A low-GPL player attacking a much stronger player gets reduced regen pause.
--
-- Server-authoritative. Runs as a heartbeat that checks active combatants
-- and applies pressure modifiers to ElementState (chakra) and StaminaState (Phase 1).
--
-- Design rationale:
--   - This is a TAX, not a hard wall. Stronger players can still beat weaker ones,
--     they just pay an exhaustion premium that compounds in extended fights.
--   - Pressure decays once combat ends — it's a fight modifier, not a permanent debuff.
--   - The ratio calc uses victim GPL as the denominator so a 100→200 GPL fight
--     applies less pressure than a 100→1000 GPL fight, scaling with absolute power gap.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─────────────────────────────────────────────
-- SAFE LOADERS
-- ─────────────────────────────────────────────

local function safeWait(parent, name, timeout)
    if not parent then
        warn(("[AuraPressure] safeWait: parent is nil for '%s'"):format(name))
        return nil
    end
    local ok, inst = pcall(function()
        return parent:WaitForChild(name, timeout)
    end)
    if not ok then
        warn(("[AuraPressure] safeWait: WaitForChild('%s') errored"):format(name))
        return nil
    end
    if not inst then
        warn(("[AuraPressure] safeWait: WaitForChild('%s') timed out"):format(name))
        return nil
    end
    return inst
end

local function safeRequire(inst, name)
    if not inst then
        warn(("[AuraPressure] safeRequire: %s is nil"):format(name))
        return nil
    end
    local className = (inst.ClassName and tostring(inst.ClassName)) or "no ClassName"
    print(("DEBUG: safeRequire target %s -> ClassName=%s typeof=%s"):format(name, className, typeof(inst)))
    if className ~= "ModuleScript" then
        warn(("[AuraPressure] safeRequire: %s is not a ModuleScript (ClassName=%s)"):format(name, className))
    end
    local ok, result = pcall(require, inst)
    if not ok then
        warn(("[AuraPressure] safeRequire: require(%s) failed: %s"):format(name, tostring(result)))
        return nil
    end
    return result
end

local sharedFolder       = safeWait(ReplicatedStorage, "Shared", 10)
local typesFolder        = safeWait(sharedFolder,      "Types",  10)
local constantsModule    = safeWait(typesFolder,       "constants",        5)
local progressionModule  = safeWait(sharedFolder,      "ProgressionState", 5)
local elementStateModule = safeWait(sharedFolder,      "ElementState",     5)

print("DEBUG: module presence:",
    "Shared=",           tostring(sharedFolder ~= nil),
    "Types=",            tostring(typesFolder ~= nil),
    "constants=",        tostring(constantsModule ~= nil),
    "ProgressionState=", tostring(progressionModule ~= nil),
    "ElementState=",     tostring(elementStateModule ~= nil)
)

local Constants        = safeRequire(constantsModule,    "constants")
local ProgressionState = safeRequire(progressionModule,  "ProgressionState")
local ElementState     = safeRequire(elementStateModule, "ElementState")

if not Constants then
    error("[AuraPressure] Constants failed to load")
end
if not ProgressionState then
    error("[AuraPressure] ProgressionState failed to load")
end
if not ElementState then
    error("[AuraPressure] ElementState failed to load")
end

local function dbg(...)
    if Constants.DEBUG then
        print("[AuraPressure]", ...)
    end
end

-- ─────────────────────────────────────────────
-- TUNING CONSTANTS
-- All numbers exposed here so balance happens in one place.
-- ─────────────────────────────────────────────

-- The threshold ratio at which pressure starts kicking in.
-- Ratio = attackerGPL / victimGPL.
-- Below MIN_RATIO_FOR_PRESSURE we don't apply any drain.
-- Above MAX_RATIO_FULL_PRESSURE we hit the maximum drain multiplier.
local MIN_RATIO_FOR_PRESSURE  = 1.5   -- attacker must be at least 1.5x victim's GPL
local MAX_RATIO_FULL_PRESSURE = 3.0   -- 3x or more = max drain

-- Stamina/chakra drain multipliers.
-- 1.0 = normal drain. 2.0 = double drain (drains 2x as fast).
-- These multiply the post-cost amount on every technique use.
local MIN_DRAIN_MULTIPLIER = 1.0      -- no extra drain
local MAX_DRAIN_MULTIPLIER = 2.0      -- 2x drain at max gap (locked spec)

-- Underdog reward: when defender is significantly weaker, they get a regen pause reduction.
-- Their post-hit pause is multiplied by this when attacker is much stronger.
local UNDERDOG_PAUSE_MULTIPLIER = 0.5 -- defender's regen pause is halved

-- Combat memory window — how long after a hit lands a player is considered "in combat"
-- with that opponent for pressure purposes. Pressure is applied during this window.
local COMBAT_MEMORY_DURATION = 8.0    -- seconds

-- Heartbeat frequency for pressure tick application.
-- Lower = more responsive but more server load. 4Hz is plenty for a stamina tax.
local TICK_RATE = 0.25  -- 4 ticks per second

-- Per-tick chakra drain when pressure is active (units per tick at max multiplier).
-- Total drain at MAX = TICK_RATE * 4 = 1 chakra per second extra at 2x multiplier.
-- This is intentionally subtle — meant to make extended fights uncomfortable,
-- not to instantly cripple stronger players.
local CHAKRA_DRAIN_PER_TICK = 0.5

-- ─────────────────────────────────────────────
-- COMBAT TRACKING
-- We track who is in combat with whom and when their last interaction was.
-- ─────────────────────────────────────────────

-- combatPairs[attackerUserId][victimUserId] = os.clock() of last hit
local combatPairs = {}

-- Pre-built reverse index for fast cleanup on player leave.
-- Updated on every Register/Tick.
local function ensurePairTable(attackerUserId)
    if not combatPairs[attackerUserId] then
        combatPairs[attackerUserId] = {}
    end
    return combatPairs[attackerUserId]
end

-- ─────────────────────────────────────────────
-- PRESSURE CALCULATION
-- Pure function — easy to test.
-- ─────────────────────────────────────────────

-- Map a clamped ratio onto a multiplier between MIN_DRAIN_MULTIPLIER and MAX_DRAIN_MULTIPLIER.
-- Linear interpolation between MIN_RATIO_FOR_PRESSURE and MAX_RATIO_FULL_PRESSURE.
local function ratioToDrainMultiplier(ratio)
    if ratio < MIN_RATIO_FOR_PRESSURE then
        return MIN_DRAIN_MULTIPLIER
    end
    if ratio >= MAX_RATIO_FULL_PRESSURE then
        return MAX_DRAIN_MULTIPLIER
    end
    -- Linear lerp
    local t = (ratio - MIN_RATIO_FOR_PRESSURE) / (MAX_RATIO_FULL_PRESSURE - MIN_RATIO_FOR_PRESSURE)
    return MIN_DRAIN_MULTIPLIER + (MAX_DRAIN_MULTIPLIER - MIN_DRAIN_MULTIPLIER) * t
end

-- Computes the pressure context between an attacker and a victim.
-- Returns:
--   {
--     active       = bool,    -- whether pressure should apply
--     ratio        = number,  -- attackerGPL / victimGPL
--     drainMult    = number,  -- multiplier to apply to drain (>=1.0 only when active)
--     underdog     = bool,    -- true if VICTIM should receive underdog protection
--   }
-- Pure function — no side effects.
local function computePressure(attackerGPL, victimGPL)
    local result = {
        active    = false,
        ratio     = 1.0,
        drainMult = MIN_DRAIN_MULTIPLIER,
        underdog  = false,
    }

    attackerGPL = tonumber(attackerGPL) or 0
    victimGPL   = tonumber(victimGPL)   or 0

    if attackerGPL <= 0 or victimGPL <= 0 then
        return result
    end

    local ratio = attackerGPL / victimGPL
    result.ratio = ratio

    if ratio >= MIN_RATIO_FOR_PRESSURE then
        result.active    = true
        result.drainMult = ratioToDrainMultiplier(ratio)
        result.underdog  = true  -- the weaker victim gets underdog perks
    end

    return result
end

-- ─────────────────────────────────────────────
-- AURA PRESSURE PUBLIC API
-- ─────────────────────────────────────────────

local AuraPressure = {}

AuraPressure.ComputePressure = computePressure

-- Called by combat handlers when a hit lands between two players.
-- This registers them as in-combat and refreshes the combat memory timer.
-- Stronger attacker hitting weaker victim → pressure starts ticking.
function AuraPressure.RegisterCombat(attacker, victim)
    if not (typeof(attacker) == "Instance" and attacker:IsA("Player")) then return end
    if not (typeof(victim)   == "Instance" and victim:IsA("Player"))   then return end
    if attacker == victim then return end

    local now = os.clock()
    ensurePairTable(attacker.UserId)[victim.UserId] = now
    ensurePairTable(victim.UserId)[attacker.UserId] = now
end

-- Returns the active pressure context for an attacker → victim relationship.
-- Returns the inactive default if not currently in combat or gap is too small.
function AuraPressure.GetPressure(attacker, victim)
    if not (typeof(attacker) == "Instance" and attacker:IsA("Player")) then
        return computePressure(0, 0)
    end
    if not (typeof(victim) == "Instance" and victim:IsA("Player")) then
        return computePressure(0, 0)
    end

    local attackerGPL = ProgressionState.GetGPL(attacker)
    local victimGPL   = ProgressionState.GetGPL(victim)
    return computePressure(attackerGPL, victimGPL)
end

-- Returns the drain multiplier that should be applied to a technique cost
-- when an attacker uses a technique against a registered combat target.
-- Used by ElementHandler to scale chakra costs.
-- If no active combat, returns 1.0 (no scaling).
function AuraPressure.GetDrainMultiplier(attacker)
    if not (typeof(attacker) == "Instance" and attacker:IsA("Player")) then
        return 1.0
    end

    local pairs = combatPairs[attacker.UserId]
    if not pairs then return 1.0 end

    local now = os.clock()
    local maxMult = 1.0

    for victimUserId, lastHitAt in pairs do
        if (now - lastHitAt) <= COMBAT_MEMORY_DURATION then
            local victim = Players:GetPlayerByUserId(victimUserId)
            if victim then
                local pressure = AuraPressure.GetPressure(attacker, victim)
                if pressure.drainMult > maxMult then
                    maxMult = pressure.drainMult
                end
            end
        end
    end

    return maxMult
end

-- Returns the regen pause multiplier for a defender being attacked.
-- Used by ElementState.PauseRegen integration — defenders being bullied
-- by much stronger attackers get faster regen recovery.
-- Returns 1.0 if not in underdog combat, UNDERDOG_PAUSE_MULTIPLIER otherwise.
function AuraPressure.GetUnderdogRegenMultiplier(defender)
    if not (typeof(defender) == "Instance" and defender:IsA("Player")) then
        return 1.0
    end

    local pairs = combatPairs[defender.UserId]
    if not pairs then return 1.0 end

    local now = os.clock()

    for attackerUserId, lastHitAt in pairs do
        if (now - lastHitAt) <= COMBAT_MEMORY_DURATION then
            local attacker = Players:GetPlayerByUserId(attackerUserId)
            if attacker then
                -- Note: attacker → defender direction
                local pressure = AuraPressure.GetPressure(attacker, defender)
                if pressure.underdog then
                    return UNDERDOG_PAUSE_MULTIPLIER
                end
            end
        end
    end

    return 1.0
end

-- ─────────────────────────────────────────────
-- HEARTBEAT — applies passive chakra drain to stronger attackers in active combat
-- ─────────────────────────────────────────────

local accumulator = 0
local function onHeartbeat(dt)
    accumulator = accumulator + dt
    if accumulator < TICK_RATE then return end
    accumulator = accumulator - TICK_RATE

    local now = os.clock()

    -- Walk every registered combat pair and apply pressure to the stronger side
    for attackerUserId, victims in pairs(combatPairs) do
        local attacker = Players:GetPlayerByUserId(attackerUserId)
        if not attacker then
            -- Cleanup orphaned entry
            combatPairs[attackerUserId] = nil
        else
            local toRemove = nil
            for victimUserId, lastHitAt in pairs(victims) do
                if (now - lastHitAt) > COMBAT_MEMORY_DURATION then
                    toRemove = toRemove or {}
                    table.insert(toRemove, victimUserId)
                else
                    local victim = Players:GetPlayerByUserId(victimUserId)
                    if victim then
                        local pressure = AuraPressure.GetPressure(attacker, victim)
                        if pressure.active then
                            -- Tick passive drain on the stronger attacker
                            local drainAmount = CHAKRA_DRAIN_PER_TICK * pressure.drainMult
                            pcall(function()
                                ElementState.DeductChakra(attacker, drainAmount)
                            end)
                        end
                    end
                end
            end

            if toRemove then
                for _, victimUserId in ipairs(toRemove) do
                    victims[victimUserId] = nil
                end
                if next(victims) == nil then
                    combatPairs[attackerUserId] = nil
                end
            end
        end
    end
end

RunService.Heartbeat:Connect(onHeartbeat)

-- ─────────────────────────────────────────────
-- PLAYER LIFECYCLE
-- ─────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(player)
    local userId = player.UserId
    combatPairs[userId] = nil
    -- Also clear this player from anyone else's combat table
    for _, victims in pairs(combatPairs) do
        victims[userId] = nil
    end
end)

-- ─────────────────────────────────────────────
-- SELF TEST
-- Verify pressure formula behaves correctly under representative scenarios.
-- ─────────────────────────────────────────────

if Constants.DEBUG then
    task.spawn(function()
        task.wait(3)

        -- Scenario 1: equal GPL → no pressure
        local p1 = computePressure(100, 100)
        assert(p1.active == false, "equal GPL should not trigger pressure")
        assert(p1.drainMult == 1.0, "equal GPL drain mult should be 1.0")
        assert(p1.underdog == false, "equal GPL — no underdog")
        dbg(string.format("[self-test] equal GPL: active=false drainMult=%.2f ✓", p1.drainMult))

        -- Scenario 2: 1.4x GPL → no pressure (below threshold)
        local p2 = computePressure(140, 100)
        assert(p2.active == false, "1.4x ratio should be below pressure threshold")
        dbg(string.format("[self-test] 1.4x ratio: active=false ✓ (below threshold %.1f)", MIN_RATIO_FOR_PRESSURE))

        -- Scenario 3: 1.5x GPL → pressure starts (at threshold)
        local p3 = computePressure(150, 100)
        assert(p3.active == true, "1.5x ratio should activate pressure")
        assert(p3.drainMult == MIN_DRAIN_MULTIPLIER, "at threshold drainMult should be MIN")
        dbg(string.format("[self-test] 1.5x ratio: active=true drainMult=%.2f ✓", p3.drainMult))

        -- Scenario 4: 2.25x GPL → mid-pressure
        local p4 = computePressure(225, 100)
        assert(p4.active == true)
        local expected4 = 1.0 + (2.0 - 1.0) * 0.5  -- midway between min and max
        assert(math.abs(p4.drainMult - expected4) < 0.01,
            ("2.25x mid-pressure expected ~%.2f got %.2f"):format(expected4, p4.drainMult))
        dbg(string.format("[self-test] 2.25x ratio: drainMult=%.3f (expected ~%.3f) ✓", p4.drainMult, expected4))

        -- Scenario 5: 3x GPL → max pressure
        local p5 = computePressure(300, 100)
        assert(p5.active == true)
        assert(p5.drainMult == MAX_DRAIN_MULTIPLIER, "3x ratio should hit max drain")
        dbg(string.format("[self-test] 3x ratio: drainMult=%.2f (max) ✓", p5.drainMult))

        -- Scenario 6: 5x GPL → still capped at max
        local p6 = computePressure(500, 100)
        assert(p6.drainMult == MAX_DRAIN_MULTIPLIER, "5x ratio should cap at max drain")
        dbg(string.format("[self-test] 5x ratio: drainMult=%.2f (capped at max) ✓", p6.drainMult))

        -- Scenario 7: weaker attacker → no pressure on attacker
        local p7 = computePressure(50, 100)
        assert(p7.active == false, "weaker attacker should not have pressure")
        assert(p7.underdog == false, "underdog flag is from victim's perspective in computePressure")
        dbg("[self-test] weaker attacker: no pressure on attacker ✓")

        -- Scenario 8: zero values handled gracefully
        local p8a = computePressure(0, 100)
        local p8b = computePressure(100, 0)
        assert(p8a.active == false and p8b.active == false, "zero GPL should not crash or activate")
        dbg("[self-test] zero values handled ✓")

        -- Scenario 9: monotonicity — drainMult never decreases as ratio increases
        local prev = 0
        for ratio = 1.0, 4.0, 0.1 do
            local p = computePressure(ratio * 100, 100)
            assert(p.drainMult >= prev - 0.0001, ("monotonicity violated at ratio %.2f"):format(ratio))
            prev = p.drainMult
        end
        dbg("[self-test] monotonicity verified ✓")

        -- Scenario 10: GetDrainMultiplier returns 1.0 for non-player and unregistered
        local m1 = AuraPressure.GetDrainMultiplier(nil)
        local m2 = AuraPressure.GetDrainMultiplier("notaplayer")
        assert(m1 == 1.0 and m2 == 1.0, "invalid input to GetDrainMultiplier should return 1.0")
        dbg("[self-test] GetDrainMultiplier defensive defaults ✓")

        print("[AuraPressure self-test] PASSED")
    end)
end

print("✅ AuraPressure initialized")

return AuraPressure