#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
CONFIG_FILE="${PLUGIN_ROOT}/config.json"
STATE_DIR="/tmp/doctor-who-sounds"

# Read hook input from stdin
INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')

# Exit if no event
if [[ -z "$EVENT" ]]; then
  exit 0
fi

# Load config
if [[ ! -f "$CONFIG_FILE" ]]; then
  exit 0
fi

ENABLED=$(jq -r '.enabled' "$CONFIG_FILE")
if [[ "$ENABLED" != "true" ]]; then
  exit 0
fi

VOLUME=$(jq -r '.volume // 0.5' "$CONFIG_FILE")
ACTIVE_PACK=$(jq -r '.active_pack // "new-who"' "$CONFIG_FILE")

# Map event to sound category
case "$EVENT" in
  SessionStart)      CATEGORY="greeting" ;;
  UserPromptSubmit)  CATEGORY="acknowledge" ;;
  Stop)              CATEGORY="complete" ;;
  Notification)      CATEGORY="alert" ;;
  *)                 exit 0 ;;
esac

# Check if category is enabled
CATEGORY_ENABLED=$(jq -r ".categories.${CATEGORY} // true" "$CONFIG_FILE")
if [[ "$CATEGORY_ENABLED" != "true" ]]; then
  exit 0
fi

# Load pack manifest
MANIFEST="${PLUGIN_ROOT}/packs/${ACTIVE_PACK}/manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
  exit 0
fi

# Get sounds for this category
SOUNDS_JSON=$(jq -r ".sounds.${CATEGORY} // []" "$MANIFEST")
SOUND_COUNT=$(echo "$SOUNDS_JSON" | jq 'length')

if [[ "$SOUND_COUNT" -eq 0 ]]; then
  exit 0
fi

# Pick a random sound, avoiding the last-played
mkdir -p "$STATE_DIR"
LAST_PLAYED_FILE="${STATE_DIR}/last_${CATEGORY}"
LAST_PLAYED=""
if [[ -f "$LAST_PLAYED_FILE" ]]; then
  LAST_PLAYED=$(cat "$LAST_PLAYED_FILE")
fi

# Select random sound
if [[ "$SOUND_COUNT" -eq 1 ]]; then
  INDEX=0
else
  # Try up to 3 times to avoid repeating
  for _ in 1 2 3; do
    INDEX=$((RANDOM % SOUND_COUNT))
    CANDIDATE=$(echo "$SOUNDS_JSON" | jq -r ".[$INDEX]")
    if [[ "$CANDIDATE" != "$LAST_PLAYED" ]]; then
      break
    fi
  done
fi

SOUND_FILE=$(echo "$SOUNDS_JSON" | jq -r ".[$INDEX]")
SOUND_PATH="${PLUGIN_ROOT}/sounds/${SOUND_FILE}"

# Save last-played
echo "$SOUND_FILE" > "$LAST_PLAYED_FILE"

# Check sound file exists
if [[ ! -f "$SOUND_PATH" ]]; then
  exit 0
fi

# Play sound in background (don't block the hook)
if command -v afplay &>/dev/null; then
  # macOS
  afplay -v "$VOLUME" "$SOUND_PATH" &
elif command -v paplay &>/dev/null; then
  # Linux PulseAudio
  paplay --volume="$(echo "$VOLUME * 65536" | bc | cut -d. -f1)" "$SOUND_PATH" &
elif command -v mpv &>/dev/null; then
  # Linux mpv
  mpv --no-terminal --volume="$(echo "$VOLUME * 100" | bc | cut -d. -f1)" "$SOUND_PATH" &
elif command -v aplay &>/dev/null; then
  # Linux ALSA (no volume control)
  aplay -q "$SOUND_PATH" &
fi

# Detach from background process
disown 2>/dev/null

exit 0
