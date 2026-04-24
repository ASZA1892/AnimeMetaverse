# Game Design Decisions — The Anime Metaverse

All locked-in design decisions made during pre-Phase 2 planning. This document is the source of truth. If something conflicts with an earlier GDD section, this document wins.

---

## Core Design Pillars

1. **Physical Skill Over Type Advantage** — A skilled player with a weak element still wins. Phase 1 combat is the great equaliser.
2. **Utility Over Multipliers** — Elements create mechanical interactions, not damage bonuses.
3. **Perpetual Progression** — Infinite Resonance tier ensures no one hits a wall.
4. **Meaningful Village Identity** — Permanent-feeling choice with defined defection paths.
5. **Risk Equals Reward** — Every safe option has a riskier parallel for better outcomes.
6. **Anti-P2W Absolute** — Monetisation never affects power, only expression.

---

## World Structure

### Triad Continent (Launch Map)
- **Kirin Peak** (Fire, North, elevated mountains) — protected by Inferno Drake
- **Azure Haven** (Water, South-West, coast) — protected by Abyssal Leviathan
- **Emerald Grove** (Grass, South-East, forest) — protected by Verdant Colossus
- **Neutral Temple** (Centre) — spawn, Architect appearances, main Roll Altar, no-PvP sanctuary
- **Sky Peak** (remote mountain, wildlands) — second Roll Altar, risky, better rolls, PvP enabled
- **Rogue Stronghold** (Mid-West hills) — rogue faction base, resource veins
- **Wilderness Zones** — NPC spawns, world events, Cataclysms, environmental hazards

### Post-Launch Expansion (Year 1)
- **Storm Peak** (Lightning, Far North) — new village + beast
- **Stone Hollow** (Earth, Underground) — new village + beast

Do NOT launch with 5 villages. Three at launch, expand when population grows.

---

## Player Onboarding

### First Session Flow
1. New player spawns at Neutral Temple (elementless)
2. Starts at 100 GPL
3. Honor/Karma starts at 0 (neutral)
4. Tutorial quest guides them to visit each of the three villages
5. Complete a trial at each village to unlock that element's awakening
6. Player chooses ONE element to awaken first
7. Can eventually learn others but their chosen element has 2x mastery rate

### Starting Values
- GPL: 100
- Honor: 0 (neutral)
- Stamina: 100
- Guard: 100
- Health: 100
- Village: None (Wanderer) until quest completion

---

## Element System (Phase 2 Priority)

### The Three Starter Elements
- **Fire** — obscuring (smoke), pressure (damage over time), explosive finishers
- **Water** — flow (movement), redirection (parry buffs), steam generation
- **Grass** — control (traps, roots), sustenance (healing), absorption

### Element Interactions (NOT Multipliers)

| Matchup | What Happens |
|---|---|
| Fire vs Grass | Fire burns away Grass traps and walls instantly. Grass must stay mobile, can't hide behind barriers. |
| Water vs Fire | Water creates Steam Clouds on contact with Fire. Smoke screen hides both players — stealth/sensing match. |
| Grass vs Water | Grass absorbs Water projectiles to grow larger or heal. Water must switch to Physical strikes to avoid feeding the enemy. |
| Fire vs Fire | Partial cancellation (60%), both take reduced damage, skill decides |
| Water vs Water | Partial cancellation, redirection duels, positioning battles |
| Grass vs Grass | Partial cancellation, territory control, trap warfare |

### Affinity System
Your chosen village element is your Affinity element:
- Learn techniques in Affinity element at 2x speed
- Can still learn other elements but at normal speed
- Affinity does NOT give damage bonus — only mastery speed bonus

### Environmental Leverage
Map biomes shift element behaviour:
- **Mountain Peaks** — Fire strengthened (thin air), Water weakened
- **Coastal/Rain Zones** — Water strengthened, Fire weakened
- **Deep Forest** — Grass strengthened (nature density), Fire dangerous (catches wild)
- **Wasteland** — All elements neutral, pure skill test
- **Near Volcanoes** — Fire buffed, Water evaporates faster

### Cross-Training (Late Game)
High GPL players can learn one technique from another element. Creates hybrid builds, breaks RPS through surprise. A Water-main with one Grass technique can counter-play in unexpected ways.

---

## Vital 5 System (Phase 2, After Element Foundation)

### The Five Nodes
1. **Elemental Node** (sternum area) — hit to seal opponent's element for 6 seconds
2. **Movement Node** (lower back) — hit to slow movement significantly
3. **Guard Node** (forearm) — hit to weaken blocking capability
4. **Vision Node** (temple) — hit to obscure opponent's screen briefly
5. **Chakra Node** (abdomen) — hit to drain stamina/special resources

### Precision Mechanic
- Each node has a small hitbox — harder to hit than a standard attack
- Landing a Vital 5 hit requires frame-perfect positioning and timing
- Breaks "Rock Paper Scissors" — precision beats element type
- Each element has unique debuff applied when landing specific nodes
- Reward for skilled play

### Underdog Reward
A lower-GPL player landing a Vital 5 hit on a much stronger player gains:
- Massive Mastery Boost
- Honor increase
- Possible GPL bonus

Makes "punching up" rewarding.

---

## GPL (Global Power Level) System

### Starting
Every player begins at 100 GPL.

### Gain Sources
- Defeating NPCs scaled to your level
- Completing village quests
- Winning PvP (more GPL for upsetting higher-level players)
- Vital 5 precision strikes
- Village contributions
- Rare mastery milestones

### Death Penalty (Layered)
- Losing to a weaker player: **larger GPL loss** (proportional to skill gap)
- Losing to an equal player: **moderate loss**
- Losing to a stronger player: **small loss**
- Never lose more than 5% of GPL earned in last 24h

This prevents farming and makes upsets mechanically meaningful.

### Aura Pressure (Power Gap Prevention)
A high-GPL player attacking a much lower-GPL player:
- Their stamina drains 2x faster
- Energy "strains" them
- Prevents griefing

Lower-level player landing parries or Vital 5 strikes on stronger player:
- Massive Mastery Boost
- Creates genuine underdog stories

---

## Mastery & Resonance (Infinite Progression)

### Tiers (Capped, Defined)
1. **Raw** — just learned, basic execution
2. **Refined** — reliable use, small damage boost
3. **Mastered** — polished execution, unique animation, special properties unlocked
4. **Transcendent** — elite level, visual aura changes

### Resonance (Infinite, Post-Transcendent)
Beyond Transcendent, every technique accumulates Resonance Points:
- No cap
- Each stack: +0.1% damage, +0.1% speed, +0.1% stamina efficiency
- Milestone unlocks at 100, 500, 1000, 5000, 10000 Resonance:
  - Visual evolution (colour shifts, particle density)
  - Unique sound effects
  - Signature aura patterns
- **Visible to others** as aura intensity
- Ensures veterans always have something to earn without breaking balance

---

## Honor/Karma System

### Bar Range: -100 to +100

### Honor Increases
- Defending weaker players
- Completing village quests
- Fair PvP (winning without ganking)
- Contributing to village
- Training new players (Sensei system)

### Honor Decreases
- Ganking new players
- Betraying clan
- Excessive griefing
- Low-level farming

### Effects
- High Honor (+50+): NPC discounts, exclusive quests, village promotions
- Low Honor (-50 and below): Dark NPC recruiter approaches, rogue path unlocks
- Profile Card shows Honor (toggleable by player privacy setting)
- Visible to others after first meeting

---

## Village System

### Joining
- Must complete village trial first
- Choose ONE village to pledge to
- Village becomes your faction, clan eligibility, political home

### Switching Villages
- **Normal Path:** Declare defection → 7 days as Rogue → Complete new village's Trial Quest → Pay GPL tribute → Accepted
- **Dark Path:** If Honor drops below -50, Dark NPC offers instant defection in exchange for serving the Architect's chaos (becomes shadow-aligned rogue)

### Going Rogue
- Permanent until a Kage-tier player formally pardons you
- Creates political gameplay (rogues must beg/pay real players for return)
- Rogue Stronghold has unique benefits (resource veins, custom clan crests)

### Village Roles
- **Kage** — highest ranking, determined by relative GPL within server
- **Elite Guard** — top 10% GPL in village
- **ANBU** — elite special forces (chosen, not grinded)
- **Standard Member** — full villager
- **Initiate** — newly joined, limited privileges

---

## Clan System

### Requirements
- Minimum GPL to found clan (number to be finalised during beta, scales with server average)
- Must have village membership (or be rogue for rogue clans)

### Caps
- Maximum 40% of server population per clan (prevents domination)
- With 100 player servers: max 40 members per clan

### Rogue Clans
- Can design custom Crest with in-game shape editor
- Crest appears on base walls and member cloaks
- Controls resource veins in wasteland
- Higher risk, higher reward than village clans

---

## Combat Economy

### Stamina Costs (Revised Phase 2 Values)
- Light attacks (Jab, Cross, Hook): 5 stamina
- Heavy attacks (Uppercut, GuardBreak): 10-15 stamina
- Special moves: 20-30 stamina
- Block active: 2 stamina/sec drain
- Dash: 10-28 stamina (current system)
- Regen pauses 2 seconds after being hit

This creates tactical pacing — exhausted players must disengage.

### Momentum System (Phase 2)
- Damage scales with player velocity at time of hit
- Flying Kick at sprint + fall velocity: 1.5x damage
- Standing hit: 1.0x damage (baseline)
- Encourages vertical movement and map traversal
- Makes Kirin Peak elevated terrain mechanically meaningful

---

## Roll Altar System

### Two Altars
- **Neutral Temple Altar** (safe zone, no PvP nearby) — standard rolls, Ryō cost
- **Sky Peak Altar** (remote mountain, PvP enabled) — higher quality rolls, but risk of interception

### What Rolls Contain
- Techniques (new moves)
- Summon contracts
- Beast bond fragments
- Cosmetic auras
- Element breakthroughs
- Scrolls (stored in inventory as items)

### Anti-Camping Mechanics
- Scrolls sealed for 30 minutes after rolling
- Can't be stolen during seal window
- Sky Peak rolls: no seal but much better outcomes (high risk, high reward)
- Level gates on stolen scrolls (can't use above your tier)
- Stolen scrolls decay 20% power

### Monetisation
- Ryō only (in-game currency). NEVER Robux for rolls.

---

## Death & Loot System

### Drop-On-Death Items
- Players carry "Carry Pouch" with selected items
- Pouch drops on death, lootable by attacker
- Level gate: attacker cannot use items above their own tier
- Prevents "kill noob, steal cool stuff" meta
- Soul-Bound items NEVER drop

### GPL Loss
See GPL System section above — layered based on skill gap.

### Respawn
- Default: spawn at chosen village (or Neutral Temple if unaffiliated)
- Cataclysm zones may have unique respawn rules
- Brief respawn invulnerability (3 sec) with anti-spawn-camp aura

---

## Village Beasts

### Rules
- Cannot leave village territory
- Auto-activate in defensive wars (no cost)
- Upgradeable through village investment
- Each has unique abilities tied to their element

### Non-War Uses
- **Training partner** — village members can spar against weakened beast for mastery
- **Monthly Feral Event** — beast goes briefly wild, village must calm it together (co-op boss)
- **Beast blessing** — high-sync villagers get passive aura buff inside village
- **Lore anchor** — beast remembers players, dialogue changes based on Honor/contributions

### Synchronization Meter (Phase 3)
- Use beast too often: Sync drops, beast becomes erratic, may refuse orders
- High Sync: Form Fusion (beast cloak, limited Domain Expansion equivalent)
- Rewards relationship over exploitation

---

## Summons (Replaces Pets)

### Design Philosophy
No floating ugly pets. Every companion is tactical and earned.

### Three Types
- **Summons** — contract-based, stamina cost to call, fight briefly alongside you, dismiss after combat (Naruto's dogs, frogs, crows model)
- **Beasts** — persistent tamed creatures, require bonding, can be ridden, not always visible (Shenron / Hagoromo rabbit model)
- **Companions** — one-use per fight, extremely powerful, long cooldown (Gamabunta boss summon model)

### Acquisition
- Roll Altar contracts (common summons)
- Quest rewards (signature summons)
- Beast bond fragments (tamed through time investment)
- Rogue alternative: Dark Summons from Architect's chaos

---

## War System (Phase 3)

### Declaration
- Village Kage can declare war on another village
- Requires village resource investment
- 24 hour cooldown between wars
- Wars last until one side concedes or 48 hours pass

### Three Phases
1. **Phase 1 — Attacker's Assault** (Defender's village, defending beast fully active)
2. **Phase 2 — Counter-Strike** (Attacker's village, their beast defends now)
3. **Phase 3 — Wasteland Reckoning** (Neutral ground, no beasts, pure skill)

### Infrastructure Targets
Not just TDM. Missions include:
- Destroy the Spirit Forge (prevents weapon crafting 24h)
- Capture the Water Tower (stamina regen debuff for enemy)
- Defend the Training Grounds (prevents enemy mastery gain)
- Non-PvP players can participate by defending or repairing

### Rewards
- Winner: GPL boost, rare resources, village pride
- Loser: Infrastructure damage, minor GPL loss, one-week rebuild period
- Exceptional individual performance: Honor, Mastery Boost, ANBU consideration

### Bounty System (Anti-Exploit)
- Bounties paid from Village Treasury (not thin air)
- Can't claim bounty on friend list or own clan
- Killed players with bounty lose Prestige
- Village Debt tracked to prevent fake-kill farming

---

## NPC Ecosystem (Phase 4)

### Wild NPCs
- **Wandering Missionaries** — medium difficulty, drop GPL and resources
- **Element Spirits** — roam near their home village, drop element materials
- **Rogue NPCs** — ex-villagers gone evil, drop rogue path items
- **Village Guards** — hostile to enemy village members
- **World Boss spawns** — rare timed events, server-wide participation

### Village NPCs
- Shopkeepers, trainers, quest givers
- Morale system: NPC behaviour changes with village state
- Peaceful village: Cheerful, 10% discounts
- Damaged village: Distressed, hide, raise prices
- Players self-police to protect economy

### Scaling
All NPCs scale with player GPL. New player and Kage both get meaningful fights.

---

## Destruction System (Phase 4)

### Pre-Fractured Swap Logic
- Buildings have "intact" and "destroyed" versions
- Damage threshold triggers swap
- No per-brick physics simulation (kills servers)

### Village Reconstruction
- Linked to Village Treasury
- Damaged buildings post "Reconstruction Missions"
- Players donate wood/stone or protect AI Workers
- Economic participation for non-PvP players

---

## Legacy System (Phase 5)

### Successor Training
- At max Resonance milestones, veterans can "Adopt" new players
- Master gets unique cosmetic (Sensei Cloak)
- Student gets 1.2x Mastery buff
- Master earns bonus for student's achievements
- Creates community retention, prevents veteran dropout

---

## Architect AI (Phase 5)

### Role
Dynamic narrative AI director. Not a boss — a reactive force.

### Behaviours
- Scales power above server's highest GPL player
- Appears after major server events (wars, betrayals)
- Creates one-off events, never repeating story beats
- Dark recruiter NPC serves Architect's chaos

### Cataclysms
- Server-wide events the Architect unleashes
- Untameable roaming world beasts (different from village beasts)
- Rare resources only available during Cataclysms
- Usually require cross-village cooperation

---

## Server Configuration

### Player Count
- 100 players per server (up from original 50)
- Rationale: 50 feels empty in an MMORPG. 200 causes mobile lag. 100 is sweet spot.

### Zone Rendering
- Only render players in same zone as local player
- Prevents performance degradation at full server capacity
- Makes wilderness feel intimate, villages feel bustling

### Cross-Platform
- PC: Core competitive experience, full feature set
- Mobile: Accessible parity, on-screen buttons reach feature equivalence
- Console: Controller support (Phase 3)
- All platforms play together on same servers

---

## Monetisation Design (Non-Negotiable)

### Ryō (In-Game Currency)
- Earned through gameplay
- Used for: Roll Altar, progression items, repairs, clan creation fees
- Never purchasable with Robux

### Robux (Real Currency)
- Used for: Cosmetics, convenience (server hops, name changes)
- NEVER: stat boosts, power-affecting items, pay-to-win gacha

### Premium Targets
- Aura cosmetics (tiered by Resonance visually, premium variants)
- Clothing and village branded outfits
- Custom clan crests
- Visual VFX themes
- Battle Pass (cosmetic tracks only)

### Free-To-Play Commitment
Every mechanic attainable without spending. Paid players look cool, don't win fights they wouldn't have won anyway.

---

## Phase Roadmap Summary

- **Phase 1 (COMPLETE):** Physical combat pipeline, multiplayer verified
- **Phase 2:** Element System, Vital 5, GPL mechanics, momentum, stamina economy
- **Phase 3:** War system, beasts, summons, clans, economy, bounty system
- **Phase 4:** Story/lore, NPC ecosystem, destruction system, rogue bases
- **Phase 5:** Legacy system, Architect AI, Cataclysms, infinite events

---

## Reference Games

Study for specific lessons:
- **Shindo Life** — combat flow, mode switching, Jutsu system design
- **Blox Fruits** — progression hooks, daily retention
- **Project Slayers** — breath/technique trees, mastery systems
- **Deepwoken** — punishment for loss, depth (but softer)
- **Aba Battlegrounds** — combat smoothness, mobile parity
- **Peroxide** — unique element matchups, technique synergies

Your competitive moats (unique features):
- Vital 5 precision targeting
- Element interactions not multipliers
- Honor/Karma system
- Relative-power progression
- Infinite Resonance
- Living village beasts
- Architect dynamic AI
