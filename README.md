# OG-Twink

A World of Warcraft 1.12 (Turtle WoW) addon for optimizing XP gains during power-leveling by managing party membership and sticky follow behavior.

## Features

### Sticky Follow
- Automatically follows your designated target when enabled
- Respects combat state and drinking detection
- Clears/restores targets intelligently to avoid interference

### Smart Party Management
Two modes for managing party membership to maximize XP:

#### Tag Mode (`/ogt twink <percent>`)
- Monitors your current target's health
- Kicks your follow target from party when target drops below specified HP%
- Automatically reinvites after 30 seconds
- Retries every second if reinvite fails
- Perfect for tagging mobs and optimizing XP splits

#### Health-Based Mode (`/ogt healtwink`)
- Monitors your own health
- Invites follow target when your HP drops below 80%
- Removes them from party when your HP exceeds 80% (during combat only)
- Keeps them in party when out of combat
- Ideal for leveling with healer support

### Auto-Accept Invites
- Automatically accepts party invites from your configured follow target
- Declines invites from other players
- Includes hardcoded exception for "Gnuzherbs"

## Commands

```
/ogt help               - Show command list
/ogt status             - Show current settings
/ogt target <name>      - Set follow target
/ogt enable             - Enable sticky follow
/ogt disable            - Disable sticky follow
/ogt healtwink          - Health-based party management
/ogt twink <percent>    - Tag at target HP% for XP optimization
```

Alternative command: `/ogtwink`

## Usage Examples

### Basic Setup
```
/ogt target Gnuzmas     # Set your follow target
/ogt enable             # Enable sticky following
```

### Tag Mode (Optimal XP per Kill)
```
/ogt twink 25           # Kick target when mob hits 25% HP
                        # Will auto-reinvite after 30 seconds
```
Use this mode when:
- You want to tag many mobs quickly
- You want full XP from solo kills
- Your follow target reinvites you between pulls

### Health-Based Mode (Continuous Healing)
```
/ogt healtwink          # Invite when HP < 80%, kick when HP > 80%
```
Use this mode when:
- You need healing support during combat
- You want to minimize XP split time
- You're grinding continuously

## Installation

1. Extract to `Interface/AddOns/OG-Twink/`
2. Ensure the folder structure is:
   ```
   Interface/
     AddOns/
       OG-Twink/
         OG-Twink.lua
         OG-Twink.toc
         README.md
   ```
3. Restart WoW or `/reload`

## Configuration

Settings are saved per character in `OGTwinkDB`:
- **Target**: Your follow target's name
- **Enabled**: Whether sticky follow is active

## Technical Details

### Reinvite System
After kicking someone with `/ogt twink`:
- First reinvite attempt: 30 seconds after kick
- Retry interval: Every 1 second
- Timeout: 65 seconds total
- Stops automatically when target rejoins

### Follow Behavior
- Pauses during combat
- Pauses while drinking (15-tick cooldown)
- Clears spell targeting cursor
- Preserves your previous target when possible

### Combat Detection
- Uses `PLAYER_REGEN_ENABLED` / `DISABLED` events
- Tracks `AUTOFOLLOW_BEGIN` / `END` states
- Respects `PlayerFrame.inCombat` status

## Credits

**Author**: Zanthor  
**Ported from**: OG-Follow twink functionality  
**Original Base**: FollowMe Enhanced (Lyriane EU-Alleria) / FollowMe (Kingen)

## Version

1.0.0 - Initial release

## License

Open source - use and modify as needed.
