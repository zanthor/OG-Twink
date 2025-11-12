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
/ogt drop               - Powerleveler: Leave party & notify twink
/ogt healtwink          - Health-based party management
/ogt twink <percent>    - Tag at target HP% for XP optimization
```

Alternative command: `/ogtwink`

## Usage Examples

### Basic Setup
```
/ogt target Gnuzmas     # Set your follow target (both characters)
/ogt enable             # Enable sticky following (twink only)
```

### Mode 1: Twink is Party Leader (Original Mode)
**On the Twink (Low Level Character):**
```
/ogt twink 25           # Kick powerleveler when mob hits 25% HP
                        # Will auto-reinvite after 30 seconds
```
Use this mode when:
- Twink is party leader
- You want to tag many mobs quickly
- You want full XP from solo kills
- Your twink manages the party

### Mode 2: Powerleveler is Party Leader (New Mode)
**On the Powerleveler (High Level Character):**
```
/ogt drop               # Leave party and notify twink
                        # Twink will request reinvite after 30s
```
Use this mode when:
- Powerleveler is party leader
- Powerleveler drops to let twink get solo XP
- Twink automatically requests reinvite after timer
- More control for the powerleveler

### Health-Based Mode (Continuous Healing)
**On the Twink:**
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

### Communication Protocol
The addon uses whispers to coordinate between characters:
- **OGTDROP**: Sent when powerleveler uses `/ogt drop`
- **OGTREQUEST**: Sent when twink requests reinvite after timer

These messages are automatically filtered - you won't see them in chat.

### Reinvite System
After kicking someone with `/ogt twink` or receiving `/ogt drop`:
- **30s**: Primary reinvite/request attempt
- **40s**: Fallback reinvite/request attempt  
- **42s+**: Continuous retry every 2 seconds
- **65s**: System times out and stops
- Stops automatically when target rejoins party

**Smart Behavior:**
- If character is party leader: Sends invites
- If character is NOT party leader: Requests invite via whisper
- Works seamlessly in both directions

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
