# Doctor Who Sounds

> Doctor Who sound effects for Claude Code. Because every coding session deserves a TARDIS.

## What It Does

This Claude Code plugin plays Doctor Who sound effects in response to session events. Hear the TARDIS materialize when you start a session, a sonic screwdriver buzz when you submit a prompt, a triumphant quote when a task completes, and a Dalek scream when a notification fires. Sounds are chosen randomly from the active pack to keep things fresh, with repeat avoidance so you won't hear the same clip twice in a row.

## Quick Install

```bash
# Clone the repo
git clone git@github.com:anthropics/doctor-who-sounds.git

# (Optional) Run setup to validate sound files
./setup.sh

# Install the plugin in Claude Code
claude /install /path/to/doctor-who-sounds
```

## Event Mapping

| Event | Sound Category | Examples |
|---|---|---|
| Session Start | `greeting` | TARDIS materialization |
| Prompt Submit | `acknowledge` | Sonic screwdriver |
| Task Complete | `complete` | TARDIS dematerialization, "Allons-y!", "Fantastic!" |
| Notification | `alert` | "EXTERMINATE!", "DELETE!", "You will be upgraded" |

## Configuration

Edit `config.json` in the plugin root to customize behavior:

```json
{
  "active_pack": "new-who",
  "volume": 0.5,
  "enabled": true,
  "categories": {
    "greeting": true,
    "acknowledge": true,
    "complete": true,
    "alert": true
  }
}
```

- **active_pack** -- which sound pack to use (matches a directory name under `packs/`)
- **volume** -- playback volume from `0.0` (silent) to `1.0` (full)
- **enabled** -- master on/off switch for all sounds
- **categories** -- toggle individual event categories on or off

## Adding Sounds

1. Drop `.mp3` files into the `sounds/` directory.
2. Reference the filenames in your pack's `manifest.json` under the appropriate category.

For example, to add a new completion sound:

```bash
cp ~/Downloads/geronimo.mp3 sounds/
```

Then add `"geronimo.mp3"` to the `complete` array in `packs/new-who/manifest.json`.

## Custom Packs

Create a new directory under `packs/` with a `manifest.json`:

```
packs/
  classic-who/
    manifest.json
```

The manifest maps sound categories to filenames in the `sounds/` directory:

```json
{
  "name": "Classic Who",
  "description": "Classic Doctor Who (1963-1989) sound effects",
  "sounds": {
    "greeting": ["classic-tardis.mp3"],
    "acknowledge": ["classic-sonic.mp3"],
    "complete": ["reversed-polarity.mp3"],
    "alert": ["exterminate-classic.mp3"]
  }
}
```

Set `"active_pack": "classic-who"` in `config.json` to switch packs.

## Platform Support

| Platform | Player | Volume Control |
|---|---|---|
| macOS | `afplay` | Yes |
| Linux (PulseAudio) | `paplay` | Yes |
| Linux (mpv) | `mpv` | Yes |
| Linux (ALSA) | `aplay` | No |

The plugin auto-detects the first available player. No extra dependencies are needed on macOS.

## Sound Sources

Need sound files? These sites offer free sound effects:

- [Pixabay](https://pixabay.com/sound-effects/) -- free sound effects, no attribution required
- [BBC Sound Effects](https://sound-effects.bbcrewind.co.uk/) -- classic BBC archive sounds
- [Orange Free Sounds](https://orangefreesounds.com/) -- free sound clips and effects

> **Note:** Sound files are not included in this repo. You'll need to source your own `.mp3` files and place them in the `sounds/` directory.

## License

[MIT](LICENSE)
