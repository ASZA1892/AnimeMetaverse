-- src/shared/Types/TechniqueDefinitions.lua
-- Pure data file. Defines all element techniques with full mastery progression.
-- Each technique has raw/refined/mastered sub-tables describing how it evolves.
-- No logic lives here.
-- Consumers:
--   ElementHandler.server.lua    — executes techniques server-side
--   TechniqueExecutor.lua        — generic processing pipeline
--   ElementController.client.lua — input binding and slot management
--   UI modules                   — display names, costs, cooldowns

local TechniqueDefinitions = {}

-- ─────────────────────────────────────────────
-- MASTERY TIERS
-- Numeric values used for interaction scaling:
--   interactionStrength = attackerTier / defenderTier
-- ─────────────────────────────────────────────

TechniqueDefinitions.Tiers = {
    Raw          = 1,
    Refined      = 2,
    Mastered     = 3,
    Transcendent = 4,
    Final        = 5,
}

-- ─────────────────────────────────────────────
-- CHAKRA COST TIERS (revised for server health)
-- ─────────────────────────────────────────────

TechniqueDefinitions.Costs = {
    Light    = 12,
    Medium   = 28,
    Heavy    = 45,
    Ultimate = 65,
    Final    = 90,
}

-- ─────────────────────────────────────────────
-- COOLDOWN TIERS in seconds (revised for server health)
-- ─────────────────────────────────────────────

TechniqueDefinitions.Cooldowns = {
    Light    = { min = 5,  max = 7   },
    Medium   = { min = 12, max = 16  },
    Heavy    = { min = 20, max = 25  },
    Ultimate = { min = 40, max = 50  },
    Final    = { min = 90, max = 120 },
}

-- ─────────────────────────────────────────────
-- ELEMENT PASSIVES
-- One per element. Applied server-side as persistent
-- player buffs. Checked by ElementHandler and TechniqueExecutor.
--
-- Fields:
--   id          string  — unique key
--   element     string  — owning element
--   name        string  — display name
--   description string  — tooltip
--   trigger     string  — when the passive activates
--                         "always" | "onParry" | "onStandingStill"
--   effect      string  — effect ID resolved by ElementInteractions
-- ─────────────────────────────────────────────

TechniqueDefinitions.Passives = {

    Fire = {
        id          = "passive_burning_ground",
        element     = "Fire",
        name        = "Burning Ground",
        description = "All Flame techniques leave smouldering patches on the terrain. "
                   .. "Enemies walking through them take DoT and are slowed.",
        trigger     = "always",       -- fires on every successful Flame technique hit
        effect      = "BurningGround",
    },

    Water = {
        id          = "passive_current_read",
        element     = "Water",
        name        = "Current Read",
        description = "Landing a parry, redirect, or Fluid Step during an enemy attack window "
                   .. "empowers your next Water technique within 4 seconds: 50% chakra cost "
                   .. "reduction and effects apply at Mastered strength regardless of actual tier.",
        trigger     = "onParry",      -- fires when GuardSystem records a successful parry
        effect      = "CurrentReadBuff",
    },

    Grass = {
        id          = "passive_living_earth",
        element     = "Grass",
        name        = "Living Earth",
        description = "Standing still on natural terrain (grass, dirt, forest floor) slowly "
                   .. "regenerates chakra and health. Rewards choosing your battlefield.",
        trigger     = "onStandingStill",  -- checked by ElementRegenerator
        effect      = "LivingEarthRegen",
    },
}

-- ─────────────────────────────────────────────
-- TECHNIQUE REGISTRY
--
-- Top-level fields (shared across all tiers):
--   id             string   — unique key
--   name           string   — display name
--   element        string   — "Fire" | "Water" | "Grass"
--   input          string   — control description (for UI tooltip)
--   costTier       string   — key into TechniqueDefinitions.Costs
--   cost           number   — resolved chakra cost
--   cooldown       number   — seconds (mid-range of tier band)
--   damageType     string   — element tag for interaction resolution
--   projectile     bool     — true = travelling part, false = instant
--   aoe            bool     — true = hits multiple targets
--   velocityScaling bool    — momentum damage scaling active
--   isFinal        bool     — true = requires setup conditions
--   vitalNodes     {string} — ordered node priorities for interaction checks
--   setup          table?   — Final only: one condition must be true to fire
--   animationId    string   — placeholder until Moon Animator
--
-- Per-tier sub-tables (raw / refined / mastered):
--   tier           number   — TechniqueDefinitions.Tiers value
--   damage         number   — base damage at this tier
--   range          number   — studs from caster
--   hitboxSize     Vector3  — server hitbox
--   effect         string?  — world effect tag spawned on hit
--   description    string   — tooltip text for this tier
-- ─────────────────────────────────────────────

local Techniques = {}

local VitalNodeSets = {
    Melee = { "Elemental", "Movement", "Guard", "Vision", "Chakra" },
    Projectile = { "Elemental", "Vision", "Chakra" },
    Wide = { "Movement", "Guard" },
    Dash = { "Movement" },
    None = {},
}

local function resolveVitalNodes(technique)
    if technique.isFinal then
        return VitalNodeSets.Wide
    end

    if technique.aoe then
        return VitalNodeSets.Wide
    end

    local tierData = technique.mastered or technique.refined or technique.raw
    if tierData and tierData.range == 0 then
        return VitalNodeSets.None
    end

    local lowerInput = string.lower(technique.input or "")
    local isDash = string.find(lowerInput, "dash", 1, true) ~= nil
        or (technique.velocityScaling == true and technique.aoe == false)
    if isDash then
        return VitalNodeSets.Dash
    end

    if technique.projectile then
        return VitalNodeSets.Projectile
    end

    return VitalNodeSets.Melee
end

-- ═══════════════════════════════════════════
-- FIRE TECHNIQUES
-- ═══════════════════════════════════════════

Techniques["fire_ember_palm"] = {
    id             = "fire_ember_palm",
    name           = "Ember Palm",
    element        = "Fire",
    input          = "M1 (close, charged)",
    costTier       = "Light",
    cost           = TechniqueDefinitions.Costs.Light,
    cooldown       = 6,
    damageType     = "Fire",
    projectile     = false,
    aoe            = false,
    velocityScaling = false,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 12,
        range       = 5,
        hitboxSize  = Vector3.new(4, 4, 4),
        effect      = "BurnDotLight",
        description = "A burning palm strike. Applies a light burn on contact.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 18,
        range       = 5,
        hitboxSize  = Vector3.new(4, 4, 4),
        effect      = "BurnDotHeavy",
        description = "Heavy burn DoT applied. Brief stagger on hit.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 26,
        range       = 6,
        hitboxSize  = Vector3.new(5, 5, 5),
        effect      = "PalmExplosion",
        description = "Palm explodes on impact. Massive stagger and knockdown. Leaves burning ground.",
    },
}

Techniques["fire_cinder_spear"] = {
    id             = "fire_cinder_spear",
    name           = "Cinder Spear",
    element        = "Fire",
    input          = "Hold M2 (charge)",
    costTier       = "Medium",
    cost           = TechniqueDefinitions.Costs.Medium,
    cooldown       = 14,
    damageType     = "Fire",
    projectile     = true,
    aoe            = false,
    velocityScaling = false,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 16,
        range       = 20,
        hitboxSize  = Vector3.new(2, 2, 2),
        effect      = "BurnDotLight",
        description = "A short fire projectile. Burns on contact.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 24,
        range       = 28,
        hitboxSize  = Vector3.new(3, 3, 3),
        effect      = "BurnDotHeavy",
        description = "Medium beam with burn DoT. Travels further.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 36,
        range       = 38,
        hitboxSize  = Vector3.new(4, 4, 4),
        effect      = "LavaTrail",
        description = "Massive flaming dragon-head beam. Leaves a lava trail on the terrain it passes through.",
    },
}

Techniques["fire_inferno_rush"] = {
    id             = "fire_inferno_rush",
    name           = "Inferno Rush",
    element        = "Fire",
    input          = "E + W (dash)",
    costTier       = "Medium",
    cost           = TechniqueDefinitions.Costs.Medium,
    cooldown       = 15,
    damageType     = "Fire",
    projectile     = false,
    aoe            = false,
    velocityScaling = true,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 14,
        range       = 12,
        hitboxSize  = Vector3.new(4, 4, 12),
        effect      = "BurnDotLight",
        description = "A flaming dash punch. Momentum scales damage.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 22,
        range       = 14,
        hitboxSize  = Vector3.new(4, 4, 14),
        effect      = "FlameTrailZone",
        description = "Dash leaves a fire trail. Enemies crossing it are burned.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 32,
        range       = 16,
        hitboxSize  = Vector3.new(5, 5, 16),
        effect      = "BurnThroughBlock",
        description = "Full-body flame charge. Burns through blocks. Leaves fire trail. Max momentum scaling.",
    },
}

Techniques["fire_flame_wall"] = {
    id             = "fire_flame_wall",
    name           = "Flame Wall",
    element        = "Fire",
    input          = "F + S (block)",
    costTier       = "Medium",
    cost           = TechniqueDefinitions.Costs.Medium,
    cooldown       = 13,
    damageType     = "Fire",
    projectile     = false,
    aoe            = false,
    velocityScaling = false,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 8,
        range       = 6,
        hitboxSize  = Vector3.new(8, 6, 1),
        effect      = "FireBarrier",
        description = "A short fire barrier. Blocks incoming attacks briefly.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 14,
        range       = 8,
        hitboxSize  = Vector3.new(10, 7, 1),
        effect      = "ReflectProjectile",
        description = "Wall reflects incoming projectiles back at the attacker.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 22,
        range       = 10,
        hitboxSize  = Vector3.new(12, 8, 1),
        effect      = "BurnOnContact",
        description = "Rising flame wall. Burns any attacker that makes contact. Leaves burning ground at base.",
    },
}

Techniques["fire_phoenix_step"] = {
    id             = "fire_phoenix_step",
    name           = "Phoenix Step",
    element        = "Fire",
    input          = "Q + M2",
    costTier       = "Heavy",
    cost           = TechniqueDefinitions.Costs.Heavy,
    cooldown       = 22,
    damageType     = "Fire",
    projectile     = false,
    aoe            = false,
    velocityScaling = false,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 10,
        range       = 10,
        hitboxSize  = Vector3.new(4, 4, 4),
        effect      = "FireTrail",
        description = "Short teleport with a fire trail. Brief i-frames during movement.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 18,
        range       = 14,
        hitboxSize  = Vector3.new(5, 5, 5),
        effect      = "BurningAfterimage",
        description = "Leaves a burning afterimage at origin point that damages anyone nearby.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 28,
        range       = 18,
        hitboxSize  = Vector3.new(6, 6, 6),
        effect      = "PhoenixRebirth",
        description = "Full phoenix rebirth dash. Extended i-frames, damage on exit, burning afterimage at origin.",
    },
}

Techniques["fire_volcanic_eruption"] = {
    id             = "fire_volcanic_eruption",
    name           = "Volcanic Eruption",
    element        = "Fire",
    input          = "M2 (ground slam, charged)",
    costTier       = "Ultimate",
    cost           = TechniqueDefinitions.Costs.Ultimate,
    cooldown       = 45,
    damageType     = "Fire",
    projectile     = false,
    aoe            = true,
    velocityScaling = false,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 30,
        range       = 12,
        hitboxSize  = Vector3.new(12, 4, 12),
        effect      = "GroundFireBurst",
        description = "A ground fire burst beneath the caster. Knocks nearby enemies back.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 45,
        range       = 16,
        hitboxSize  = Vector3.new(16, 6, 16),
        effect      = "EruptionLaunch",
        description = "Eruption launches opponents upward. Larger fire zone persists briefly.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 62,
        range       = 22,
        hitboxSize  = Vector3.new(22, 8, 22),
        effect      = "LavaExplosionZone",
        description = "Massive AoE lava explosion. Persistent lava terrain. Anyone caught is launched and burned.",
    },
}

Techniques["fire_solar_judgement"] = {
    id             = "fire_solar_judgement",
    name           = "Solar Judgement",
    element        = "Fire",
    input          = "Channel + M1 + M2",
    costTier       = "Final",
    cost           = TechniqueDefinitions.Costs.Final,
    cooldown       = 100,
    damageType     = "Fire",
    projectile     = false,
    aoe            = true,
    velocityScaling = false,
    isFinal        = true,
    setup = {
        requireGuardBroken       = true,
        requireNodeSealed        = true,
        requireMomentumFull      = true,
        requireCharge            = true,
        requireFavourableTerrain = true,
    },
    animationId    = "rbxassetid://0",

    -- Final moves do not evolve through raw/refined/mastered.
    -- They are unlocked at Transcendent tier as a complete technique.
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Final,
        damage      = 85,
        range       = 30,
        hitboxSize  = Vector3.new(30, 10, 30),
        effect      = "FireDomain",
        description = "Calls down a sun-fragment. Creates a Fire Domain that denies the battlefield "
                   .. "for 15 seconds. All burning ground inside is amplified.",
    },
}

-- ═══════════════════════════════════════════
-- WATER TECHNIQUES
-- ═══════════════════════════════════════════

Techniques["water_ripple_strike"] = {
    id             = "water_ripple_strike",
    name           = "Ripple Strike",
    element        = "Water",
    input          = "M1 (close)",
    costTier       = "Light",
    cost           = TechniqueDefinitions.Costs.Light,
    cooldown       = 6,
    damageType     = "Water",
    projectile     = false,
    aoe            = false,
    velocityScaling = false,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 11,
        range       = 5,
        hitboxSize  = Vector3.new(4, 4, 4),
        effect      = "SoakDebuffLight",
        description = "A water-coated punch. Applies light Soak — reduces enemy fire technique strength briefly.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 17,
        range       = 5,
        hitboxSize  = Vector3.new(4, 4, 4),
        effect      = "SoakDebuffHeavy",
        description = "Soaks target heavily. Weakens all fire techniques applied to them.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 24,
        range       = 6,
        hitboxSize  = Vector3.new(5, 5, 5),
        effect      = "Disorient",
        description = "Concussive shockwave on impact. Brief disorient. Soak debuff at full strength.",
    },
}

Techniques["water_hydro_bolt"] = {
    id             = "water_hydro_bolt",
    name           = "Hydro Bolt",
    element        = "Water",
    input          = "Hold M2 (charge)",
    costTier       = "Medium",
    cost           = TechniqueDefinitions.Costs.Medium,
    cooldown       = 14,
    damageType     = "Water",
    projectile     = true,
    aoe            = false,
    velocityScaling = false,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 14,
        range       = 22,
        hitboxSize  = Vector3.new(2, 2, 2),
        effect      = "SoakDebuffLight",
        description = "A compact water bullet. Fast travel time.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 22,
        range       = 28,
        hitboxSize  = Vector3.new(2, 2, 2),
        effect      = "PierceThrough",
        description = "Pierces through one target. Hits anyone behind the first.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 32,
        range       = 35,
        hitboxSize  = Vector3.new(3, 3, 3),
        effect      = "BlockPierce",
        description = "Pressurised lance. Ignores blocks entirely — deals chip damage regardless. Soaks on hit.",
    },
}

Techniques["water_fluid_step"] = {
    id             = "water_fluid_step",
    name           = "Fluid Step",
    element        = "Water",
    input          = "F + tap during enemy attack",
    costTier       = "Medium",
    cost           = TechniqueDefinitions.Costs.Medium,
    cooldown       = 13,
    damageType     = "Water",
    projectile     = false,
    aoe            = false,
    velocityScaling = true,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 12,
        range       = 6,
        hitboxSize  = Vector3.new(5, 5, 5),
        effect      = "WaterTrail",
        description = "Sidestep with a water trail. Avoids the attack on successful read.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 20,
        range       = 6,
        hitboxSize  = Vector3.new(5, 5, 5),
        effect      = "ParryCounter",
        description = "Successful read triggers an instant counter strike.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 30,
        range       = 7,
        hitboxSize  = Vector3.new(6, 6, 6),
        effect      = "AttackRedirect",
        description = "Full redirection — opponent's attack momentum is turned against them. Triggers Current Read passive.",
    },
}

Techniques["water_mist_veil"] = {
    id             = "water_mist_veil",
    name           = "Mist Veil",
    element        = "Water",
    input          = "F + W",
    costTier       = "Medium",
    cost           = TechniqueDefinitions.Costs.Medium,
    cooldown       = 15,
    damageType     = "Water",
    projectile     = false,
    aoe            = false,
    velocityScaling = false,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 0,
        range       = 8,
        hitboxSize  = Vector3.new(8, 6, 8),
        effect      = "MistCloudLight",
        description = "A brief vision-obscuring mist around the caster. Breaks target lock on enemies nearby.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 0,
        range       = 10,
        hitboxSize  = Vector3.new(10, 6, 10),
        effect      = "MistHeal",
        description = "Mist heals the caster slightly over its duration. Larger radius.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 0,
        range       = 14,
        hitboxSize  = Vector3.new(14, 8, 14),
        effect      = "DenseFogDebuff",
        description = "Dense fog hides caster completely. Debuffs enemy accuracy on outgoing techniques. Self-heal on duration.",
    },
}

Techniques["water_riptide_pull"] = {
    id             = "water_riptide_pull",
    name           = "Riptide Pull",
    element        = "Water",
    input          = "Q + M1",
    costTier       = "Heavy",
    cost           = TechniqueDefinitions.Costs.Heavy,
    cooldown       = 23,
    damageType     = "Water",
    projectile     = false,
    aoe            = false,
    velocityScaling = false,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 14,
        range       = 16,
        hitboxSize  = Vector3.new(3, 3, 3),
        effect      = "ShortPull",
        description = "A short pull. Drags the target a short distance toward the caster.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 22,
        range       = 20,
        hitboxSize  = Vector3.new(3, 3, 3),
        effect      = "StrongPull",
        description = "Yanks opponent fully into melee range.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 32,
        range       = 24,
        hitboxSize  = Vector3.new(4, 4, 4),
        effect      = "SoakOnPull",
        description = "Strong pull into melee range. Applies Soak on arrival. Triggers Current Read passive if timed during enemy attack.",
    },
}

Techniques["water_tsunami_surge"] = {
    id             = "water_tsunami_surge",
    name           = "Tsunami Surge",
    element        = "Water",
    input          = "M2 (sweep, charged)",
    costTier       = "Ultimate",
    cost           = TechniqueDefinitions.Costs.Ultimate,
    cooldown       = 45,
    damageType     = "Water",
    projectile     = false,
    aoe            = true,
    velocityScaling = false,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 28,
        range       = 14,
        hitboxSize  = Vector3.new(14, 6, 8),
        effect      = "WavePushLight",
        description = "A small wave that pushes nearby enemies back.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 42,
        range       = 18,
        hitboxSize  = Vector3.new(18, 7, 10),
        effect      = "WavePushHeavy",
        description = "Larger wave, knocks back further. Soaks ground on contact.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 58,
        range       = 24,
        hitboxSize  = Vector3.new(24, 8, 12),
        effect      = "TerrainWash",
        description = "Massive wave. Terrain-flooding wash. Creates steam clouds on contact with any fire effects.",
    },
}

Techniques["water_abyssal_current"] = {
    id             = "water_abyssal_current",
    name           = "Abyssal Current",
    element        = "Water",
    input          = "Channel + M1 + M2",
    costTier       = "Final",
    cost           = TechniqueDefinitions.Costs.Final,
    cooldown       = 110,
    damageType     = "Water",
    projectile     = false,
    aoe            = true,
    velocityScaling = false,
    isFinal        = true,
    setup = {
        requireGuardBroken       = true,
        requireNodeSealed        = true,
        requireMomentumFull      = true,
        requireCharge            = true,
        requireFavourableTerrain = true,
    },
    animationId    = "rbxassetid://0",

    mastered = {
        tier        = TechniqueDefinitions.Tiers.Final,
        damage      = 80,
        range       = 35,
        hitboxSize  = Vector3.new(35, 10, 35),
        effect      = "TerrainFlood",
        description = "Floods the entire arena. Slows all enemies. Empowers all Water techniques for 20 seconds. "
                   .. "Caster moves freely through the flood.",
    },
}

-- ═══════════════════════════════════════════
-- GRASS TECHNIQUES
-- ═══════════════════════════════════════════

Techniques["grass_thorn_lash"] = {
    id             = "grass_thorn_lash",
    name           = "Thorn Lash",
    element        = "Grass",
    input          = "M1 (close)",
    costTier       = "Light",
    cost           = TechniqueDefinitions.Costs.Light,
    cooldown       = 6,
    damageType     = "Grass",
    projectile     = false,
    aoe            = false,
    velocityScaling = false,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 11,
        range       = 7,
        hitboxSize  = Vector3.new(3, 3, 7),
        effect      = "VineWhip",
        description = "A vine whip strike. Extended range for a melee hit.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 17,
        range       = 8,
        hitboxSize  = Vector3.new(3, 3, 8),
        effect      = "RootBrief",
        description = "Whip applies a brief Root on hit. Target cannot dash during root.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 24,
        range       = 10,
        hitboxSize  = Vector3.new(4, 4, 10),
        effect      = "PullThenRoot",
        description = "Whip pulls target into melee range then applies Root. Combo setup.",
    },
}

Techniques["grass_seed_volley"] = {
    id             = "grass_seed_volley",
    name           = "Seed Volley",
    element        = "Grass",
    input          = "Hold M2 (charge)",
    costTier       = "Medium",
    cost           = TechniqueDefinitions.Costs.Medium,
    cooldown       = 13,
    damageType     = "Grass",
    projectile     = true,
    aoe            = false,
    velocityScaling = false,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 12,
        range       = 20,
        hitboxSize  = Vector3.new(2, 2, 2),
        effect      = "SeedSingle",
        description = "A single seed projectile. Roots on hit.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 18,
        range       = 22,
        hitboxSize  = Vector3.new(2, 2, 2),
        effect      = "SeedSpread",
        description = "Multi-seed spread. One seed roots on contact. Others slow.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 28,
        range       = 26,
        hitboxSize  = Vector3.new(3, 3, 3),
        effect      = "BouncingBarrage",
        description = "Bouncing seed barrage. Each seed carries a Root proc. Hard to dodge all of them.",
    },
}

Techniques["grass_thorn_trap"] = {
    id             = "grass_thorn_trap",
    name           = "Thorn Trap",
    element        = "Grass",
    input          = "E + S (place)",
    costTier       = "Light",
    cost           = TechniqueDefinitions.Costs.Light,
    cooldown       = 7,
    damageType     = "Grass",
    projectile     = false,
    aoe            = false,
    velocityScaling = false,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 10,
        range       = 12,
        hitboxSize  = Vector3.new(5, 1, 5),
        effect      = "ThornTrapZone",
        description = "Places a hidden ground trap. Roots the first enemy to step on it.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 15,
        range       = 14,
        hitboxSize  = Vector3.new(6, 1, 6),
        effect      = "ThornTrapLarge",
        description = "Trap stays hidden longer. Larger trigger radius.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 22,
        range       = 14,
        hitboxSize  = Vector3.new(6, 1, 6),
        effect      = "ThornPillarExplosion",
        description = "Trap explodes into a thorn pillar on trigger. Larger damage and extended root duration.",
    },
}

Techniques["grass_regrowth"] = {
    id             = "grass_regrowth",
    name           = "Regrowth",
    element        = "Grass",
    input          = "F + W (channel)",
    costTier       = "Medium",
    cost           = TechniqueDefinitions.Costs.Medium,
    cooldown       = 14,
    damageType     = "Grass",
    projectile     = false,
    aoe            = false,
    velocityScaling = false,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 0,
        range       = 0,
        hitboxSize  = Vector3.new(0, 0, 0),
        effect      = "HealOverTimeLight",
        description = "Slow self-heal over 5 seconds. Cannot activate while stunned.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 0,
        range       = 0,
        hitboxSize  = Vector3.new(0, 0, 0),
        effect      = "HealPlusDamageResist",
        description = "Heal over time with a brief damage resistance window during channeling.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 0,
        range       = 0,
        hitboxSize  = Vector3.new(0, 0, 0),
        effect      = "HealAndCleanse",
        description = "Heal pulse cleanses one active debuff. Resistance window extended. Living Earth passive amplified during channel.",
    },
}

Techniques["grass_verdant_wall"] = {
    id             = "grass_verdant_wall",
    name           = "Verdant Wall",
    element        = "Grass",
    input          = "F + S (block)",
    costTier       = "Medium",
    cost           = TechniqueDefinitions.Costs.Medium,
    cooldown       = 15,
    damageType     = "Grass",
    projectile     = false,
    aoe            = false,
    velocityScaling = false,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 0,
        range       = 8,
        hitboxSize  = Vector3.new(10, 7, 1),
        effect      = "VineBarrier",
        description = "A short vine barrier. Blocks incoming attacks. Weaker against fire.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 10,
        range       = 10,
        hitboxSize  = Vector3.new(12, 8, 1),
        effect      = "AbsorbWater",
        description = "Wall absorbs incoming Water projectiles and heals the caster for the absorbed damage.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 18,
        range       = 12,
        hitboxSize  = Vector3.new(14, 9, 1),
        effect      = "ThornCounterWall",
        description = "Wall sprouts thorns. Melee attackers take damage on hit. Still absorbs Water. Leaves thorn trap at base.",
    },
}

Techniques["grass_verdant_prison"] = {
    id             = "grass_verdant_prison",
    name           = "Verdant Prison",
    element        = "Grass",
    input          = "M2 (ground slam, charged)",
    costTier       = "Ultimate",
    cost           = TechniqueDefinitions.Costs.Ultimate,
    cooldown       = 46,
    damageType     = "Grass",
    projectile     = false,
    aoe            = true,
    velocityScaling = false,
    isFinal        = false,
    animationId    = "rbxassetid://0",

    raw = {
        tier        = TechniqueDefinitions.Tiers.Raw,
        damage      = 26,
        range       = 12,
        hitboxSize  = Vector3.new(12, 4, 12),
        effect      = "RootPatch",
        description = "A root patch erupts beneath nearby enemies. Brief immobilise.",
    },
    refined = {
        tier        = TechniqueDefinitions.Tiers.Refined,
        damage      = 40,
        range       = 16,
        hitboxSize  = Vector3.new(16, 6, 16),
        effect      = "VineCage",
        description = "A cage of vines rises. Extends root duration significantly.",
    },
    mastered = {
        tier        = TechniqueDefinitions.Tiers.Mastered,
        damage      = 56,
        range       = 20,
        hitboxSize  = Vector3.new(20, 8, 20),
        effect      = "ThornArena",
        description = "Massive thorn arena erupts from the ground. All enemies inside are rooted. Terrain becomes living earth.",
    },
}

Techniques["grass_world_tree"] = {
    id             = "grass_world_tree",
    name           = "World Tree",
    element        = "Grass",
    input          = "Channel + M1 + M2",
    costTier       = "Final",
    cost           = TechniqueDefinitions.Costs.Final,
    cooldown       = 115,
    damageType     = "Grass",
    projectile     = false,
    aoe            = true,
    velocityScaling = false,
    isFinal        = true,
    setup = {
        requireGuardBroken       = true,
        requireNodeSealed        = true,
        requireMomentumFull      = true,
        requireCharge            = true,
        requireFavourableTerrain = true,
    },
    animationId    = "rbxassetid://0",

    mastered = {
        tier        = TechniqueDefinitions.Tiers.Final,
        damage      = 70,
        range       = 28,
        hitboxSize  = Vector3.new(28, 15, 28),
        effect      = "WorldTreeDomain",
        description = "A colossal world tree dominates the arena for 20 seconds. "
                   .. "Heals allies over time. Roots all enemies. "
                   .. "Absorbs all incoming projectiles. Living Earth passive active across entire domain.",
    },
}

for _, technique in pairs(Techniques) do
    technique.vitalNodes = resolveVitalNodes(technique)
end

-- ─────────────────────────────────────────────
-- LOOKUP HELPERS
-- ─────────────────────────────────────────────

TechniqueDefinitions.Techniques = Techniques

function TechniqueDefinitions.GetTechnique(id)
    return Techniques[id] or nil
end

-- Returns the correct tier sub-table for a technique at a given mastery level.
-- Falls back to raw if the requested tier sub-table doesn't exist.
function TechniqueDefinitions.GetTierData(id, tierName)
    local t = Techniques[id]
    if not t then return nil end
    local key = string.lower(tierName)
    -- Final moves only have "mastered" sub-table
    if t.isFinal then return t.mastered end
    return t[key] or t.raw
end

-- Returns all techniques for an element, sorted tier ascending.
function TechniqueDefinitions.GetByElement(element)
    local result = {}
    for _, technique in pairs(Techniques) do
        if technique.element == element then
            table.insert(result, technique)
        end
    end
    table.sort(result, function(a, b)
        local aTier = a.raw and a.raw.tier or a.mastered.tier
        local bTier = b.raw and b.raw.tier or b.mastered.tier
        return aTier < bTier
    end)
    return result
end

-- Returns default slot loadout for an element (up to 4 slots).
-- Auto-fills with non-Final techniques, tier ascending.
-- Final moves must be manually slotted.
function TechniqueDefinitions.GetDefaultLoadout(element)
    local all = TechniqueDefinitions.GetByElement(element)
    local loadout = {}
    for _, technique in ipairs(all) do
        if not technique.isFinal then
            table.insert(loadout, technique.id)
            if #loadout >= 4 then break end
        end
    end
    return loadout
end

function TechniqueDefinitions.IsFinalMove(id)
    local t = TechniqueDefinitions.GetTechnique(id)
    return t ~= nil and t.isFinal == true
end

-- Returns the passive table for an element or nil.
function TechniqueDefinitions.GetPassive(element)
    return TechniqueDefinitions.Passives[element] or nil
end

print("✅ TechniqueDefinitions loaded — " .. (function()
    local count = 0
    for _ in pairs(Techniques) do count = count + 1 end
    return count
end)() .. " techniques registered across " .. #{"Fire","Water","Grass"} .. " elements")

return TechniqueDefinitions