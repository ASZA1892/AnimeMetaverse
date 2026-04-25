-- src/shared/Types/ElementDefinitions.lua
-- Pure data file. Defines element properties and interaction rules.
-- No logic lives here — TechniqueExecutor and ElementInteractions.lua
-- consume this data and handle the actual gameplay effects.

local ElementDefinitions = {}

-- ─────────────────────────────────────────────
-- ELEMENT REGISTRY
-- ─────────────────────────────────────────────

ElementDefinitions.Elements = {

    Fire = {
        name            = "Fire",
        village         = "Kirin Peak",
        affinityBonus   = 2.0,     -- 2x mastery rate for affinity holders (all elements share this, explicit here for clarity)

        -- Visual identity — used by VFX and UI modules
        color           = Color3.fromRGB(255, 80, 20),
        secondaryColor  = Color3.fromRGB(255, 200, 50),
        particleTexture = "rbxassetid://0",   -- placeholder, replace with Moon Animator assets

        -- Gameplay flavour tags — read by future tooltip/UI systems
        tags            = { "pressure", "damage_over_time", "obscuring" },

        -- Environmental modifiers (Phase 3 map biomes)
        -- Multiplier applied to technique effectiveness in that zone
        environmentBonus = {
            KirinPeak   = 1.25,   -- home mountain, thin air
            CoastalZone = 0.80,
            DeepForest  = 0.90,   -- fire spreads dangerously but less controlled
            Wasteland   = 1.00,
            NearVolcano = 1.40,
        },

        -- Interaction rules: what happens when a Fire technique
        -- contacts an active effect belonging to the named element.
        -- Keys are element names, values are interaction IDs resolved
        -- by ElementInteractions.lua on the server.
        interactions = {
            Grass = "burn_trap",      -- Fire destroys Grass traps/walls instantly, no roots applied
            Water = "create_steam",   -- Fire AoE + Water projectile → steam cloud, obscures vision
            Fire  = "partial_cancel", -- Mirror matchup — 60% mutual damage reduction
        },
    },

    Water = {
        name            = "Water",
        village         = "Azure Haven",
        affinityBonus   = 2.0,

        color           = Color3.fromRGB(40, 140, 255),
        secondaryColor  = Color3.fromRGB(180, 230, 255),
        particleTexture = "rbxassetid://0",

        tags            = { "flow", "redirection", "steam_generation" },

        environmentBonus = {
            CoastalZone = 1.30,
            RainZone    = 1.30,
            KirinPeak   = 0.75,   -- thin dry air weakens water
            NearVolcano = 0.60,   -- evaporates faster
            Wasteland   = 1.00,
        },

        interactions = {
            Fire  = "create_steam",   -- Water hits Fire AoE → steam cloud
            Grass = "grass_absorb",   -- Grass user absorbs Water projectile to heal/grow
            Water = "partial_cancel", -- Mirror — redirection duels, positioning battles
        },
    },

    Grass = {
        name            = "Grass",
        village         = "Emerald Grove",
        affinityBonus   = 2.0,

        color           = Color3.fromRGB(50, 200, 80),
        secondaryColor  = Color3.fromRGB(180, 255, 120),
        particleTexture = "rbxassetid://0",

        tags            = { "control", "traps", "sustenance", "absorption" },

        environmentBonus = {
            DeepForest  = 1.30,
            CoastalZone = 1.10,   -- moisture aids growth
            KirinPeak   = 0.80,   -- sparse vegetation
            NearVolcano = 0.70,
            Wasteland   = 1.00,
        },

        interactions = {
            Water = "grass_absorb",   -- Grass absorbs incoming Water, heals or grows barrier
            Fire  = "burn_trap",      -- Grass traps/walls are destroyed instantly by Fire
            Grass = "partial_cancel", -- Mirror — territory control, trap warfare
        },
    },
}

-- ─────────────────────────────────────────────
-- INTERACTION SEVERITY TABLE
-- Defines whether an interaction favours the attacker or defender.
-- Used by ElementInteractions.lua to decide who gets penalised.
-- "counter"  = attacker wins cleanly (e.g. Fire burns Grass trap)
-- "neutral"  = both affected equally (e.g. partial cancel)
-- "backfire" = attacker is disadvantaged (e.g. Water feeding Grass)
-- ─────────────────────────────────────────────

ElementDefinitions.InteractionSeverity = {
    burn_trap      = "counter",
    create_steam   = "neutral",
    grass_absorb   = "backfire",
    partial_cancel = "neutral",
}

-- ─────────────────────────────────────────────
-- LOOKUP HELPERS
-- ─────────────────────────────────────────────

-- Returns the element table or nil if not found.
function ElementDefinitions.GetElement(name)
    return ElementDefinitions.Elements[name] or nil
end

-- Returns the interaction ID between attackingElement and
-- the element of the effect being contacted, or nil if none.
function ElementDefinitions.GetInteraction(attackingElement, contactElement)
    local el = ElementDefinitions.GetElement(attackingElement)
    if not el then return nil end
    return el.interactions[contactElement] or nil
end

-- Returns the environmental modifier for an element in a given zone.
-- Defaults to 1.0 (no change) if zone not defined for that element.
function ElementDefinitions.GetEnvironmentBonus(elementName, zoneName)
    local el = ElementDefinitions.GetElement(elementName)
    if not el then return 1.0 end
    return (el.environmentBonus and el.environmentBonus[zoneName]) or 1.0
end

-- Returns a flat list of all valid element name strings.
function ElementDefinitions.GetAllElementNames()
    local names = {}
    for name in pairs(ElementDefinitions.Elements) do
        table.insert(names, name)
    end
    return names
end

print("✅ ElementDefinitions loaded — " .. #ElementDefinitions.GetAllElementNames() .. " elements registered")

return ElementDefinitions