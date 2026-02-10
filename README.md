# Botgrade

A turn-based tactical deck-building roguelike where you pilot a robot through a hostile city, fighting enemy robots and scavenging their parts to upgrade your own.

Built with [Elixir](https://elixir-lang.org/), [Phoenix LiveView](https://github.com/phoenixframework/phoenix_live_view), and [Tailwind CSS](https://tailwindcss.com/).

## The Game

You are a robot navigating a procedurally-generated city full of rogue machines. Combat is card-based: your robot's components (weapons, armor, batteries, CPUs) are all cards in your deck. Each turn you draw a hand, power up your batteries to roll dice, allocate those dice to activate your weapons and defenses, and try to destroy your opponent before they destroy you.

When you win a fight, you scavenge the wreckage for parts to add to your deck. Damaged components still work, but with penalties -- a cracked battery rolls lower, a busted CPU misfires a third of the time. Build your deck, push deeper into the city, and survive.

### Game Modes

- **Campaign** -- Navigate branching paths through city zones with escalating danger ratings, shops, and a story to uncover (story TBD)
- **Quick Combat** -- Jump straight into fights with scaling difficulty every 5 rounds

### Combat

Each turn follows a sequence:

1. **Draw** -- Draw cards from your deck
2. **Power Up** -- Activate batteries to roll dice, allocate dice to card slots, use CPU abilities, and fire weapons
3. **Enemy Turn** -- The opponent activates their own cards against you

### Card Types

| Type | Role |
|------|------|
| **Battery** | Roll dice to power other cards. Characteristics: dice count, die sides, max activations |
| **Weapon** | Deal kinetic, energy, or plasma damage. Some have dual-mode defense capabilities |
| **Armor** | Provide shields (vs energy) or plating (vs kinetic). Plasma bypasses both |
| **CPU** | Special abilities available once per turn: discard/draw, reflex block, target lock, overclock, siphon power |
| **Chassis** | Your robot's hit points |
| **Capacitor** | Store dice for later use |
| **Utility**| Special abilities available if drawn: dice manipulation, extra damage |
| **Locomotion** | Movement capability |

### Damage System

Three damage types interact with two defense types:

|  | Plating | Shields |
|--|---------|---------|
| **Kinetic** | Full absorption | 25% absorption |
| **Energy** | 25% absorption | Full absorption |
| **Plasma** | Bypasses | Bypasses |

### Enemy Archetypes

- **Rogue** -- Balanced generalist
- **Ironclad** -- Heavy tank with high HP and kinetic weapons
- **Strikebolt** -- Glass cannon with multiple weapons and weak components
- **Hexapod** -- Versatile fighter using all three damage types

## Setup

Prerequisites: [Elixir](https://elixir-lang.org/install) ~> 1.15

```bash
mix setup
```

This installs dependencies and builds frontend assets.

## Running

```bash
mix phx.server
```

Then visit [localhost:4000](http://localhost:4000).

## Tests

```bash
mix test
```

Or run the full precommit suite (compile with warnings-as-errors, format check, tests):

```bash
mix precommit
```

## Project Structure

```
lib/
  botgrade/
    game/           # Core game logic (combat, cards, dice, damage, scavenging)
    combat/         # Combat GenServer and supervision
    campaign/       # Campaign state, persistence, and supervision
  botgrade_web/
    live/           # LiveView modules (combat_live, campaign_live)
    components/     # UI components (combat, campaign, core)
    controllers/    # Page controller
test/
  botgrade/         # Game logic tests
```

## License

CC BY-SA-NC
