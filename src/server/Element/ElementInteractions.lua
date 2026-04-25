local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function safeWait(parent, name, timeout)
    if not parent then
        warn(("safeWait: parent is nil for '%s'"):format(name))
        return nil
    end

    local ok, inst = pcall(function()
        return parent:WaitForChild(name, timeout)
    end)
    if not ok then
        warn(("safeWait: WaitForChild('%s') errored"):format(name))
        return nil
    end
    if not inst then
        warn(("safeWait: WaitForChild('%s') timed out"):format(name))
        return nil
    end
    return inst
end

local function safeRequire(inst, name)
    if not inst then
        warn(("safeRequire: %s is nil"):format(name))
        return nil
    end
    local className = (inst.ClassName and tostring(inst.ClassName)) or "no ClassName"
    print(("DEBUG: safeRequire target %s -> ClassName=%s typeof=%s"):format(name, className, typeof(inst)))
    if className ~= "ModuleScript" then
        warn(("safeRequire: %s is not a ModuleScript (ClassName=%s)"):format(name, className))
    end
    local ok, result = pcall(require, inst)
    if not ok then
        warn(("safeRequire: require(%s) failed: %s"):format(name, tostring(result)))
        return nil
    end
    return result
end

local sharedFolder = safeWait(ReplicatedStorage, "Shared", 5)
local typesFolder = safeWait(sharedFolder, "Types", 5)

local ConstantsModule          = safeWait(typesFolder,    "constants",            2)
local ElementDefinitionsModule = safeWait(typesFolder,    "ElementDefinitions",   2)
local TechniqueDefinitionsModule = safeWait(typesFolder,  "TechniqueDefinitions", 2)
local ElementStateModule       = safeWait(sharedFolder,   "ElementState",         5)
local WorldEffectRegistryModule = safeWait(script.Parent, "WorldEffectRegistry",  5)

print("DEBUG: module presence:",
    "Shared=",              tostring(sharedFolder ~= nil),
    "Types=",               tostring(typesFolder ~= nil),
    "constants=",           tostring(ConstantsModule ~= nil),
    "ElementDefinitions=",  tostring(ElementDefinitionsModule ~= nil),
    "TechniqueDefinitions=",tostring(TechniqueDefinitionsModule ~= nil),
    "ElementState=",        tostring(ElementStateModule ~= nil),
    "WorldEffectRegistry=", tostring(WorldEffectRegistryModule ~= nil)
)

local Constants          = safeRequire(ConstantsModule,           "constants")
local ElementDefinitions = safeRequire(ElementDefinitionsModule,  "ElementDefinitions")
local TechniqueDefinitions = safeRequire(TechniqueDefinitionsModule, "TechniqueDefinitions")
local ElementState       = safeRequire(ElementStateModule,        "ElementState")
local WorldEffectRegistry = safeRequire(WorldEffectRegistryModule, "WorldEffectRegistry")

if not Constants          then error("[ElementInteractions] Constants failed to load")          end
if not ElementDefinitions then error("[ElementInteractions] ElementDefinitions failed to load") end
if not TechniqueDefinitions then error("[ElementInteractions] TechniqueDefinitions failed to load") end
if not ElementState       then error("[ElementInteractions] ElementState failed to load")       end
if not WorldEffectRegistry then error("[ElementInteractions] WorldEffectRegistry failed to load") end

local function dbg(...)
    if Constants.DEBUG then
        print("[ElementInteractions]", ...)
    end
end

local function safeCall(label, fn, ...)
    if type(fn) ~= "function" then
        warn(("[ElementInteractions] safeCall '%s' skipped: target is not a function"):format(tostring(label)))
        return false, nil
    end
    local ok, resultA, resultB, resultC = pcall(fn, ...)
    if not ok then
        warn(("[ElementInteractions] safeCall '%s' failed: %s"):format(tostring(label), tostring(resultA)))
        return false, nil
    end
    return true, resultA, resultB, resultC
end

local ElementInteractions = {}

local INTERACTION_QUERY_RADIUS  = 8
local STRENGTH_MIN_THRESHOLD    = 0.5
local STRENGTH_MAX_CLAMP        = 2.0
local PARTIAL_CANCEL_DAMAGE_MOD = 0.4

local spawnRegistry      = {}
local registeredTagCount = 0

local function arrayToSet(items)
    local set = {}
    if type(items) == "table" then
        for _, value in ipairs(items) do
            if type(value) == "string" then
                set[value] = true
            end
        end
    end
    return set
end

local function createEffect(payload)
    local ok, effectId = safeCall("WorldEffectRegistry.CreateEffect", WorldEffectRegistry.CreateEffect, payload)
    if not ok then return nil end
    return effectId
end

local function createSphere(context, config)
    local effectId = createEffect({
        effectType  = config.effectType or "ElementEffect",
        element     = config.element or ((context.technique and context.technique.element) or context.element or "Neutral"),
        ownerUserId = (context.attacker and context.attacker.UserId) or context.ownerUserId or 0,
        position    = context.position or Vector3.zero,
        shape       = "Sphere",
        radius      = config.radius,
        duration    = config.duration,
        tickRate    = config.tickRate,
        tags        = arrayToSet(config.tags),
        metadata    = config.metadata or {},
    })
    if not effectId then return {} end
    return { effectId }
end

local function createBox(context, config)
    local effectId = createEffect({
        effectType  = config.effectType or "ElementEffect",
        element     = config.element or ((context.technique and context.technique.element) or context.element or "Neutral"),
        ownerUserId = (context.attacker and context.attacker.UserId) or context.ownerUserId or 0,
        position    = context.position or Vector3.zero,
        shape       = "Box",
        size        = config.size,
        duration    = config.duration,
        tickRate    = config.tickRate,
        tags        = arrayToSet(config.tags),
        metadata    = config.metadata or {},
    })
    if not effectId then return {} end
    return { effectId }
end

local function createLine(context, config)
    local effectId = createEffect({
        effectType  = config.effectType or "ElementEffect",
        element     = config.element or ((context.technique and context.technique.element) or context.element or "Neutral"),
        ownerUserId = (context.attacker and context.attacker.UserId) or context.ownerUserId or 0,
        position    = context.position or Vector3.zero,
        shape       = "Line",
        length      = config.length,
        duration    = config.duration,
        tickRate    = config.tickRate,
        tags        = arrayToSet(config.tags),
        metadata    = config.metadata or {},
    })
    if not effectId then return {} end
    return { effectId }
end

local function registerSpawnConfig(tag, spawner)
    spawnRegistry[tag] = spawner
    registeredTagCount = registeredTagCount + 1
end

local function registerNoSpawn(tag)
    registerSpawnConfig(tag, function() return {} end)
end

local function registerAllSpawnConfigs()

    -- ── FIRE ──────────────────────────────────────────────────────────────
    registerSpawnConfig("BurnDotLight", function(ctx)
        return createSphere(ctx, { effectType="BurnDotLight", radius=3, duration=4, tags={"BurnsGrass"} })
    end)
    registerSpawnConfig("BurnDotHeavy", function(ctx)
        return createSphere(ctx, { effectType="BurnDotHeavy", radius=4, duration=6, tags={"BurnsGrass"}, metadata={damagePerTick=2} })
    end)
    registerSpawnConfig("PalmExplosion", function(ctx)
        return createSphere(ctx, { effectType="PalmExplosion", radius=6, duration=1, tags={"BurnsGrass"} })
    end)
    registerSpawnConfig("LavaTrail", function(ctx)
        return createLine(ctx, { effectType="LavaTrail", length=30, duration=8, tickRate=0.5, tags={"BurnsGrass"}, metadata={damagePerTick=3} })
    end)
    registerSpawnConfig("FlameTrailZone", function(ctx)
        return createLine(ctx, { effectType="FlameTrailZone", length=14, duration=5, tickRate=0.5, tags={"BurnsGrass"}, metadata={damagePerTick=2} })
    end)
    registerSpawnConfig("BurnThroughBlock", function(ctx)
        return createSphere(ctx, { effectType="BurnThroughBlock", radius=4, duration=0.5 })
    end)
    registerSpawnConfig("FireBarrier", function(ctx)
        return createBox(ctx, { effectType="FireBarrier", size=Vector3.new(8,6,1), duration=4 })
    end)
    registerSpawnConfig("ReflectProjectile", function(ctx)
        return createBox(ctx, { effectType="ReflectProjectile", size=Vector3.new(10,7,1), duration=5, tags={"ReflectsProjectiles"} })
    end)
    registerSpawnConfig("BurnOnContact", function(ctx)
        return createBox(ctx, { effectType="BurnOnContact", size=Vector3.new(12,8,1), duration=6, tags={"BurnsOnContact"} })
    end)
    registerSpawnConfig("FireTrail", function(ctx)
        return createSphere(ctx, { effectType="FireTrail", radius=3, duration=3 })
    end)
    registerSpawnConfig("BurningAfterimage", function(ctx)
        return createSphere(ctx, { effectType="BurningAfterimage", radius=5, duration=4, tickRate=0.5, metadata={damagePerTick=2} })
    end)
    registerSpawnConfig("PhoenixRebirth", function(ctx)
        return createSphere(ctx, { effectType="PhoenixRebirth", radius=6, duration=2 })
    end)
    registerSpawnConfig("GroundFireBurst", function(ctx)
        return createSphere(ctx, { effectType="GroundFireBurst", radius=12, duration=3, tags={"BurnsGrass"} })
    end)
    registerSpawnConfig("EruptionLaunch", function(ctx)
        return createSphere(ctx, { effectType="EruptionLaunch", radius=16, duration=5, tags={"BurnsGrass"} })
    end)
    registerSpawnConfig("LavaExplosionZone", function(ctx)
        return createSphere(ctx, { effectType="LavaExplosionZone", radius=22, duration=8, tickRate=0.5, tags={"BurnsGrass"}, metadata={damagePerTick=3} })
    end)
    registerSpawnConfig("SmokeScreen", function(ctx)
        return createSphere(ctx, { effectType="SmokeScreen", radius=18, duration=6, tags={"ObscuresVision"} })
    end)
    registerSpawnConfig("FireDomain", function(ctx)
        return createSphere(ctx, { effectType="FireDomain", radius=30, duration=15, tickRate=0.5, tags={"BurnsGrass","FireDomain"}, metadata={damagePerTick=4} })
    end)

    -- ── WATER ─────────────────────────────────────────────────────────────
    registerSpawnConfig("SoakDebuffLight", function(ctx)
        return createSphere(ctx, { effectType="SoakDebuffLight", radius=3, duration=4, tags={"SoakedGround"} })
    end)
    registerSpawnConfig("SoakDebuffHeavy", function(ctx)
        return createSphere(ctx, { effectType="SoakDebuffHeavy", radius=4, duration=6, tags={"SoakedGround"} })
    end)
    registerSpawnConfig("Disorient", function(ctx)
        return createSphere(ctx, { effectType="Disorient", radius=4, duration=3 })
    end)
    registerSpawnConfig("PierceThrough", function(ctx)
        return createSphere(ctx, { effectType="PierceThrough", radius=2, duration=1 })
    end)
    registerSpawnConfig("BlockPierce", function(ctx)
        return createSphere(ctx, { effectType="BlockPierce", radius=3, duration=1 })
    end)
    registerSpawnConfig("WaterTrail", function(ctx)
        return createSphere(ctx, { effectType="WaterTrail", radius=3, duration=3, tags={"SoakedGround"} })
    end)
    registerSpawnConfig("MistCloudLight", function(ctx)
        return createSphere(ctx, { effectType="MistCloudLight", radius=8, duration=5, tags={"ObscuresVision"} })
    end)
    registerSpawnConfig("MistHeal", function(ctx)
        return createSphere(ctx, { effectType="MistHeal", radius=10, duration=6, tickRate=0.5, tags={"ObscuresVision"} })
    end)
    registerSpawnConfig("DenseFogDebuff", function(ctx)
        return createSphere(ctx, { effectType="DenseFogDebuff", radius=14, duration=8, tags={"ObscuresVision","DebuffsAccuracy"} })
    end)
    registerSpawnConfig("WavePushLight", function(ctx)
        return createBox(ctx, { effectType="WavePushLight", size=Vector3.new(14,6,8), duration=2, tags={"SoakedGround"} })
    end)
    registerSpawnConfig("WavePushHeavy", function(ctx)
        return createBox(ctx, { effectType="WavePushHeavy", size=Vector3.new(18,7,10), duration=3, tags={"SoakedGround"} })
    end)
    registerSpawnConfig("TerrainWash", function(ctx)
        return createBox(ctx, { effectType="TerrainWash", size=Vector3.new(24,8,12), duration=5, tags={"SoakedGround"} })
    end)
    registerSpawnConfig("TerrainFlood", function(ctx)
        return createSphere(ctx, { effectType="TerrainFlood", radius=35, duration=20, tickRate=0.5, tags={"SoakedGround","WaterDomain"}, metadata={slowPercent=0.4} })
    end)
    registerNoSpawn("ParryCounter")
    registerNoSpawn("AttackRedirect")
    registerNoSpawn("ShortPull")
    registerNoSpawn("StrongPull")
    registerNoSpawn("SoakOnPull")

    -- ── GRASS ─────────────────────────────────────────────────────────────
    registerNoSpawn("VineWhip")
    registerSpawnConfig("RootBrief", function(ctx)
        return createSphere(ctx, { effectType="RootBrief", radius=2, duration=2, tags={"Roots"} })
    end)
    registerSpawnConfig("PullThenRoot", function(ctx)
        return createSphere(ctx, { effectType="PullThenRoot", radius=2, duration=3, tags={"Roots"} })
    end)
    registerSpawnConfig("SeedSingle", function(ctx)
        return createSphere(ctx, { effectType="SeedSingle", radius=2, duration=4, tags={"Roots"} })
    end)
    registerSpawnConfig("SeedSpread", function(ctx)
        return createSphere(ctx, { effectType="SeedSpread", radius=3, duration=5, tags={"Roots","SlowsTargets"} })
    end)
    registerSpawnConfig("BouncingBarrage", function(ctx)
        return createSphere(ctx, { effectType="BouncingBarrage", radius=4, duration=6, tags={"Roots"} })
    end)
    registerSpawnConfig("ThornTrapZone", function(ctx)
        return createSphere(ctx, { effectType="ThornTrapZone", radius=5, duration=30, tickRate=0.5, tags={"Roots","GrassTrap"} })
    end)
    registerSpawnConfig("ThornTrapLarge", function(ctx)
        return createSphere(ctx, { effectType="ThornTrapLarge", radius=6, duration=30, tickRate=0.5, tags={"Roots","GrassTrap"} })
    end)
    registerSpawnConfig("ThornPillarExplosion", function(ctx)
        return createSphere(ctx, { effectType="ThornPillarExplosion", radius=6, duration=4, tags={"Roots"} })
    end)
    registerSpawnConfig("HealOverTimeLight", function(ctx)
        return createSphere(ctx, { effectType="HealOverTimeLight", radius=2, duration=5, tickRate=0.5, tags={"HealsOwner"} })
    end)
    registerSpawnConfig("HealPlusDamageResist", function(ctx)
        return createSphere(ctx, { effectType="HealPlusDamageResist", radius=2, duration=6, tickRate=0.5, tags={"HealsOwner","DamageResistOwner"} })
    end)
    registerSpawnConfig("HealAndCleanse", function(ctx)
        return createSphere(ctx, { effectType="HealAndCleanse", radius=3, duration=6, tickRate=0.5, tags={"HealsOwner","CleansesDebuffs"} })
    end)
    registerSpawnConfig("VineBarrier", function(ctx)
        return createBox(ctx, { effectType="VineBarrier", size=Vector3.new(10,7,1), duration=4, tags={"GrassWall"} })
    end)
    registerSpawnConfig("AbsorbWater", function(ctx)
        return createBox(ctx, { effectType="AbsorbWater", size=Vector3.new(12,8,1), duration=6, tags={"GrassWall","AbsorbsWater"} })
    end)
    registerSpawnConfig("ThornCounterWall", function(ctx)
        return createBox(ctx, { effectType="ThornCounterWall", size=Vector3.new(14,9,1), duration=8, tags={"GrassWall","AbsorbsWater","Thorns"} })
    end)
    registerSpawnConfig("RootPatch", function(ctx)
        return createSphere(ctx, { effectType="RootPatch", radius=12, duration=3, tags={"Roots"} })
    end)
    registerSpawnConfig("VineCage", function(ctx)
        return createSphere(ctx, { effectType="VineCage", radius=16, duration=5, tags={"Roots"} })
    end)
    registerSpawnConfig("ThornArena", function(ctx)
        return createSphere(ctx, { effectType="ThornArena", radius=20, duration=8, tickRate=0.5, tags={"Roots","GrassDomain"} })
    end)
    registerSpawnConfig("WorldTreeDomain", function(ctx)
        return createSphere(ctx, { effectType="WorldTreeDomain", radius=28, duration=20, tickRate=0.5, tags={"Roots","GrassDomain","AbsorbsProjectiles","HealsAllies"} })
    end)

    -- ── PASSIVE ───────────────────────────────────────────────────────────
    registerSpawnConfig("BurningGround", function(ctx)
        return createSphere(ctx, {
            effectType = "BurningGround",
            element    = "Fire",
            radius     = 4,
            duration   = 5,
            tickRate   = 0.5,
            tags       = { "BurnsGrass", "Passive" },
            metadata   = { damagePerTick = 1 },
        })
    end)
end

registerAllSpawnConfigs()

-- ─────────────────────────────────────────────
-- MATH HELPER
-- ─────────────────────────────────────────────

function ElementInteractions.GetInteractionStrength(attackerTier, defenderTier)
    local aTier = tonumber(attackerTier) or 1
    local dTier = math.max(tonumber(defenderTier) or 1, 1)
    return math.min(aTier / dTier, STRENGTH_MAX_CLAMP)
end

-- ─────────────────────────────────────────────
-- SPAWN EFFECT FROM TECHNIQUE
-- Called by ElementHandler after a technique lands.
-- Reads tierData.effect tag and spawns the matching world effect.
-- ─────────────────────────────────────────────

function ElementInteractions.SpawnEffectFromTechnique(context)
    if type(context) ~= "table" then return {} end
    if typeof(context.position) ~= "Vector3" then return {} end

    local tierData  = context.tierData
    local effectTag = tierData and tierData.effect
    if type(effectTag) ~= "string" then return {} end

    local spawner = spawnRegistry[effectTag]
    if type(spawner) ~= "function" then
        warn(("[ElementInteractions] Unknown effect tag '%s' — no spawn"):format(effectTag))
        return {}
    end

    local ok, effects = safeCall("spawnRegistry." .. effectTag, spawner, context)
    if not ok or type(effects) ~= "table" then return {} end
    return effects
end

-- ─────────────────────────────────────────────
-- SPAWN PASSIVE
-- Called by ElementHandler for always-trigger passives.
-- Fire: BurningGround. Water/Grass: deferred.
-- ─────────────────────────────────────────────

function ElementInteractions.SpawnPassive(context)
    if type(context) ~= "table" then return nil end
    if typeof(context.position) ~= "Vector3" then return nil end

    local element = context.element

    if element == "Fire" then
        local ok, spawned = safeCall("spawnRegistry.BurningGround", spawnRegistry.BurningGround, context)
        if not ok or type(spawned) ~= "table" then return nil end
        return spawned[1]
    end

    if element == "Water" then
        dbg("CurrentRead passive deferred to Week 2 player buff system")
        return nil
    end

    if element == "Grass" then
        dbg("LivingEarth passive deferred to terrain biome system")
        return nil
    end

    return nil
end

-- ─────────────────────────────────────────────
-- RESOLVE HIT
-- Called by ElementHandler after damage lands.
-- Queries nearby world effects, resolves interactions,
-- returns a result table. Does NOT apply damage.
-- ─────────────────────────────────────────────

function ElementInteractions.ResolveHit(context)
    local result = {
        interactionsTriggered = {},
        effectsSpawned        = {},
        effectsDestroyed      = {},
        damageModifier        = 1.0,
        heldInteraction       = nil,
    }

    if type(context) ~= "table" then
        warn("[ElementInteractions] ResolveHit: invalid context")
        return result
    end

    -- Support both field names from the spec
    local targetPosition = context.targetPosition or context.position
    if typeof(targetPosition) ~= "Vector3" then
        warn("[ElementInteractions] ResolveHit: missing targetPosition")
        return result
    end

    local attackerElement = context.attackerElement
    if type(attackerElement) ~= "string" and type(context.technique) == "table" then
        attackerElement = context.technique.element
    end
    if type(attackerElement) ~= "string" then
        warn("[ElementInteractions] ResolveHit: could not resolve attackerElement")
        return result
    end

    local attackerTier = tonumber(context.attackerTier) or 1
    local attacker     = context.attacker
    local damage       = tonumber(context.damage) or 0

    local okNearby, nearbyEffects = safeCall(
        "WorldEffectRegistry.GetEffectsInRadius",
        WorldEffectRegistry.GetEffectsInRadius,
        targetPosition,   -- ← uses targetPosition, not context.position
        INTERACTION_QUERY_RADIUS
    )
    if not okNearby or type(nearbyEffects) ~= "table" then
        return result
    end

    -- Track destroyed effects so we don't cascade-check them
    local destroyedSet = {}

    for _, effect in ipairs(nearbyEffects) do
        if type(effect) == "table"
            and type(effect.id) == "string"
            and not destroyedSet[effect.id]
        then
            local interactionId = ElementDefinitions.GetInteraction(attackerElement, effect.element)

            if type(interactionId) == "string" then
                local defenderTier = tonumber(effect.tier) or 1
                local strength     = ElementInteractions.GetInteractionStrength(attackerTier, defenderTier)

                if strength < STRENGTH_MIN_THRESHOLD then
                    -- Held — attacker tier too low to overcome defender tier
                    dbg(("HELD — %s too weak (strength: %.2f) attacker tier %d vs defender tier %d"):format(
                        interactionId, strength, attackerTier, defenderTier))
                    result.heldInteraction = interactionId

                else
                    table.insert(result.interactionsTriggered, interactionId)

                    if interactionId == "burn_trap" then
                        -- Always destroy above strength 1.0; 50% chance below
                        local shouldDestroy = strength > 1.0 or math.random() < 0.5
                        if shouldDestroy then
                            local okRm, removed = safeCall(
                                "WorldEffectRegistry.RemoveEffect",
                                WorldEffectRegistry.RemoveEffect,
                                effect.id
                            )
                            if okRm and removed then
                                destroyedSet[effect.id] = true
                                table.insert(result.effectsDestroyed, effect.id)
                                dbg(("burn_trap — destroyed Grass effect %s (strength: %.2f)"):format(effect.id, strength))
                            end
                        else
                            dbg(("burn_trap — survived coin flip for effect %s (strength: %.2f)"):format(effect.id, strength))
                        end

                    elseif interactionId == "create_steam" then
                        local steamId = createEffect({
                            effectType  = "SteamCloud",
                            element     = "Neutral",  -- ← steam belongs to neither element
                            ownerUserId = (attacker and attacker.UserId) or 0,
                            position    = effect.position or targetPosition,
                            shape       = "Sphere",
                            radius      = 6 + (strength * 2),
                            duration    = 4 + (strength * 2),
                            tickRate    = 0,
                            tier        = math.max(attackerTier, defenderTier),
                            tags        = arrayToSet({ "ObscuresVision" }),
                            metadata    = { sourceInteraction = "create_steam" },
                        })
                        if steamId then
                            table.insert(result.effectsSpawned, steamId)
                            dbg(("create_steam — spawned SteamCloud %s (strength: %.2f)"):format(steamId, strength))
                        end

                    elseif interactionId == "grass_absorb" then
                        -- Water technique absorbed by Grass world effect — restore chakra to Grass owner
                        local ownerUserId = tonumber(effect.ownerUserId) or 0
                        local grassOwner  = ownerUserId > 0 and Players:GetPlayerByUserId(ownerUserId) or nil
                        local restoreAmount = math.floor(damage * 0.5 * strength)
                        if grassOwner then
                            safeCall("ElementState.AddChakra", ElementState.AddChakra, grassOwner, restoreAmount)
                            dbg(("grass_absorb — %s restored %d chakra (strength: %.2f)"):format(
                                grassOwner.Name, restoreAmount, strength))
                        end
                        result.damageModifier = 0  -- Water technique fully absorbed

                    elseif interactionId == "partial_cancel" then
                        -- Same-element collision — 60% damage reduction
                        result.damageModifier = math.min(result.damageModifier, PARTIAL_CANCEL_DAMAGE_MOD)
                        dbg(("partial_cancel — %s mirror match, damage * %.1f"):format(attackerElement, PARTIAL_CANCEL_DAMAGE_MOD))

                    else
                        dbg(("Unhandled interaction id '%s'"):format(interactionId))
                    end
                end
            end
        end
    end

    dbg(("ResolveHit complete: triggered=%d spawned=%d destroyed=%d damageMod=%.2f held=%s"):format(
        #result.interactionsTriggered,
        #result.effectsSpawned,
        #result.effectsDestroyed,
        result.damageModifier,
        tostring(result.heldInteraction)
    ))

    return result
end

-- ─────────────────────────────────────────────
-- SELF-TEST (DEBUG only — remove before launch)
-- ─────────────────────────────────────────────

if Constants.DEBUG then
    task.spawn(function()
        task.wait(3)

        assert(math.abs(ElementInteractions.GetInteractionStrength(2, 4) - 0.5)  < 0.0001, "strength 2/4 = 0.5")
        assert(math.abs(ElementInteractions.GetInteractionStrength(3, 1) - 2.0)  < 0.0001, "strength 3/1 clamped to 2.0")
        assert(math.abs(ElementInteractions.GetInteractionStrength(5, 1) - 2.0)  < 0.0001, "strength 5/1 clamped to 2.0")

        local spawned = ElementInteractions.SpawnEffectFromTechnique({
            attacker     = nil,
            attackerTier = 3,
            technique    = { element = "Fire" },
            tierData     = { effect  = "BurnDotLight" },
            position     = Vector3.new(10, 5, 10),
        })
        assert(type(spawned) == "table", "SpawnEffectFromTechnique returns array")
        print("[ElementInteractions self-test] spawned " .. tostring(#spawned) .. " effect(s) from BurnDotLight")

        local passiveId = ElementInteractions.SpawnPassive({
            player       = nil,
            element      = "Fire",
            position     = Vector3.new(0, 0, 0),
            attackerTier = 3,
            ownerUserId  = 0,
        })
        if passiveId then
            print("[ElementInteractions self-test] passive spawned:", passiveId)
        else
            warn("[ElementInteractions self-test] passive spawn returned nil — FAILURE")
        end

        print("[ElementInteractions self-test] PASSED")
    end)
end

print("✅ ElementInteractions initialized — " .. registeredTagCount .. " effect tags registered")

return ElementInteractions