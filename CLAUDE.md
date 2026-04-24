# The Anime Metaverse — Project Context

## Who I Am
Alan (ASZA1892). Solo developer building The Anime Metaverse — a Roblox anime MMORPG blending Naruto (world structure, villages), JJK (tactical combat depth), and Dragon Ball (spectacle, power scaling). Started April 2026.

## Core Vision
An anti-P2W, infinitely progressive anime MMO where physical skill beats type advantage, villages have identity, and every player's journey feels meaningful. Three infinite loops drive retention: Mastery (personal growth), Power (gear and aura), and World (events, wars, legacy).

## Tech Stack
- **Engine:** Roblox (Luau)
- **Sync:** Rojo serve on localhost:34872
- **Package manager:** Wally
- **IDE:** Cursor + Roblox Studio
- **Repo:** https://github.com/ASZA1892/AnimeMetaverse.git (private)
- **Project path:** C:\Dev\AnimeMetaverse
- **Tools path:** C:\Dev\Tools\ (rojo.exe, wally.exe)

## Coding Standards
- Use `task.wait()` and `task.spawn()` — never deprecated `wait()` or `delay()`
- Use `LinearVelocity` or `AssemblyLinearVelocity` — never `BodyVelocity`
- Server-authoritative combat: all damage, cooldowns, stamina calculated server-side
- Client only handles inputs and local visual FX
- Module scripts use `.lua`, Scripts use `.server.lua` or `.client.lua`
- Safe require patterns with pcall wrappers for all external modules
- Debug prints gated behind `Constants.DEBUG` flag
- Use WeakKey metatables (`{__mode = "k"}`) for player-indexed cleanup tables

## Critical Security Rules
- Never trust client-sent damage values
- Rate limit all combat RPCs (attack interval minimum 0.1s)
- Validate state transitions server-side before processing any action
- Sanitize all client data (typeof checks, range clamps)
- Anti-P2W is non-negotiable — no paid stat boosts ever

## Output Style Preferences
- Be direct, minimal preamble
- Full paste-over code blocks when asked
- Disagree with me if my logic has flaws — don't just agree
- Break complex changes into small testable steps
- Flag when a feature should be deferred to a later phase

## Monetisation Principles (Never Break)
- **Ryō** — in-game currency for progression items (earned, not bought)
- **Robux** — cosmetics and convenience only (auras, clothing, visual VFX)
- NEVER: paid stat boosts, gacha that affects power, P2W mechanics
- Battle Pass: cosmetic tracks only
- Roll Altar: uses in-game Ryō only, NEVER Robux

## Current Development Phase
Phase 1 COMPLETE as of April 24, 2026. Currently transitioning to Phase 2 (Element System).

## Key Design Pillars
1. **Physical dominance** — Phase 1 combat is the great equaliser. Skilled players always have a chance regardless of element matchup.
2. **Elemental utility not multipliers** — elements create mechanical interactions (Fire burns traps, Water creates steam, Grass absorbs water) instead of damage bonuses.
3. **Perpetual progression** — infinite Resonance tier beyond Mastered. No ceiling.
4. **Village identity** — permanent-feeling choice with defection path, not casual swapping.
5. **Risk equals reward** — safer routes available but optimal rewards require risk.
6. **Anti-P2W absolute** — monetisation never affects power, only expression.

## Reference Documents
- `Phase1_Handoff.md` — complete Phase 1 code architecture and state
- `Phase2_Plan.md` — Element System design and build order
- `GameDesignDecisions.md` — all locked-in design decisions from pre-Phase 2 planning
- `.cursorrules` — Cursor-specific coding rules

## How To Work With Me
One feature per chat. When starting a new chat:
1. Read CLAUDE.md
2. Read relevant Phase document
3. Ask what I'm building today
4. Plan before code — outline logic, I approve, then code
5. Test immediately, no polishing unstable features
