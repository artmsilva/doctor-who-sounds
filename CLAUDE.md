# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin that plays Doctor Who sound effects in response to session events (start, prompt submit, task complete, notification). Distributed via the Claude Code plugin marketplace.

## Commands

```bash
make install        # Build Rust binary (release) and copy to bin/
make daemon-start   # Start the background daemon manually
make daemon-stop    # Stop the running daemon
make daemon-status  # Check if daemon is running
./setup.sh          # Validate environment, sound files, and test playback
```

## Architecture

```
src/main.rs                   # Single Rust binary: client, daemon, and stop modes
bin/play-sound                # Compiled binary (committed, built via `make install`)
hooks/hooks.json              # Registers 4 Claude Code hook events → bin/play-sound
hooks/scripts/play-sound.sh   # Legacy bash implementation (unused, kept for reference)
config.json                   # User config: active pack, volume, enabled, category toggles
packs/<pack>/manifest.json    # Maps sound categories to .mp3 filenames
sounds/*.mp3                  # Actual audio files (committed to repo)
Cargo.toml                    # Rust deps: serde_json, libc (no others)
.claude-plugin/plugin.json    # Plugin manifest (name, version, hooks path)
.claude-plugin/marketplace.json  # Marketplace listing metadata
```

### Daemon Architecture

The binary has three modes, selected by CLI args:

- `play-sound` (no args) — **client mode** (what hooks call). Reads stdin, sends event JSON to the daemon over a Unix domain socket at `/tmp/doctor-who-sounds/daemon.sock`, exits in ~3-4ms. Auto-spawns daemon if not running. Falls back to fork-based direct play if daemon is unreachable.
- `play-sound --daemon` — **daemon mode**. Long-running process that listens on the Unix socket, spawns a thread per connection, plays sounds directly. Managed via PID file at `/tmp/doctor-who-sounds/daemon.pid` with atomic creation (O_EXCL). Signal handling: SIGTERM/SIGINT for clean shutdown, SIGCHLD ignored for automatic zombie reaping.
- `play-sound --stop` — **stop mode**. Reads PID file, sends SIGTERM, waits for cleanup.

### Event Flow

1. Claude Code fires a hook event (SessionStart, UserPromptSubmit, Stop, Notification)
2. `hooks.json` routes all 4 events to `bin/play-sound` (client mode)
3. Client reads stdin (capped at 8KB), connects to daemon socket, writes event JSON, exits
4. Daemon thread parses `hook_event_name`, maps to category, reads config/manifest, spawns audio player
5. If daemon not running: client auto-spawns it, retries connection (up to 200ms)
6. If daemon unreachable: falls back to fork-based direct play (original behavior)

### Sound Packs

Each pack is a directory under `packs/` with a `manifest.json` that maps the 4 categories to arrays of filenames in `sounds/`. The `new-who` pack is the only pack currently. All sound files live in a flat `sounds/` directory shared across packs.

## Key Constraints

- Hook timeout is 10 seconds (set in hooks.json); client mode exits in ~3-4ms
- Audio player is auto-detected once and cached at `/tmp/doctor-who-sounds/player`
- `CLAUDE_PLUGIN_ROOT` env var resolves paths; binary falls back to `current_exe()` parent resolution
- Sound files are `.mp3` and committed directly to the repo (not gitignored)
- Plugin structure follows the `.claude-plugin/` convention with `plugin.json` pointing to `hooks/hooks.json`
- Daemon state lives in `/tmp/doctor-who-sounds/` (socket, PID file, player cache, last-played files)
