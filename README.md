# Doctor Who Sounds

> Doctor Who sound effects for Claude Code. Because every coding session deserves a TARDIS.

## What It Does

This Claude Code plugin plays Doctor Who sound effects in response to session events. Hear the TARDIS materialize when you start a session, a sonic screwdriver buzz when you submit a prompt, a triumphant quote when a task completes, and a Dalek scream when a notification fires. Sounds are chosen randomly from the active pack to keep things fresh, with repeat avoidance so you won't hear the same clip twice in a row.

## Install

```bash
# Add the marketplace
/plugin marketplace add asilva/doctor-who-sounds

# Install the plugin
/plugin install doctor-who-sounds@doctor-who-sounds
```

Sound files and a pre-built binary are included -- it works out of the box on macOS. Restart Claude Code after installing.

## Event Mapping

| Event | Sound Category | Examples |
|---|---|---|
| Session Start | `greeting` | TARDIS materialization |
| Prompt Submit | `acknowledge` | Sonic screwdriver |
| Task Complete | `complete` | TARDIS dematerialization, "Allons-y!", "Fantastic!" |
| Notification | `alert` | "EXTERMINATE!", "DELETE!" |

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

## How It Works

The plugin uses a daemon architecture for minimal latency (~3-4ms per hook event):

1. Claude Code fires a hook event and invokes `bin/play-sound`
2. The binary connects to a background daemon via Unix domain socket
3. If no daemon is running, the client auto-spawns one
4. The daemon plays the sound; the client exits immediately

The daemon stays alive across all hook events, eliminating process startup overhead. If the daemon is unreachable, the client falls back to direct playback.

```bash
# Manual daemon management (usually not needed -- auto-spawns on first event)
make daemon-status    # Check if daemon is running
make daemon-stop      # Stop the daemon
make daemon-restart   # Restart the daemon
```

## Building from Source

The pre-built binary in `bin/` works on macOS (arm64). To rebuild:

```bash
# Requires Rust toolchain
make install    # cargo build --release + copy to bin/
```

## Troubleshooting

**Sounds not playing?**
- Restart Claude Code after installing the plugin
- Check `config.json` has `"enabled": true`
- Run `./setup.sh` to validate sound files and audio player
- Check daemon status: `make daemon-status`
- Restart the daemon: `make daemon-restart`

**Wrong sounds?**
- Check `packs/new-who/manifest.json` for the category-to-file mapping
- Verify the sound files exist in `sounds/`

## Sound Sources

Need more sound files? These sites offer free sound effects:

- [Pixabay](https://pixabay.com/sound-effects/) -- free sound effects, no attribution required
- [BBC Sound Effects](https://sound-effects.bbcrewind.co.uk/) -- classic BBC archive sounds
- [Orange Free Sounds](https://orangefreesounds.com/) -- free sound clips and effects

## License

[MIT](LICENSE)
