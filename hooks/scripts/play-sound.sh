#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
STATE_DIR="/tmp/doctor-who-sounds"

# Consume stdin synchronously (Claude Code blocks until this completes)
# read -r -d '' avoids spawning a cat subprocess
INPUT=""
read -r -d '' INPUT || true

# Fork everything else into background so the hook returns immediately
(
  CONFIG_FILE="${PLUGIN_ROOT}/config.json"
  CACHE_FILE="${STATE_DIR}/cache.sh"

  # Extract event name with bash regex -- no jq needed
  if [[ "$INPUT" =~ \"hook_event_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    EVENT="${BASH_REMATCH[1]}"
  else
    exit 0
  fi

  # Map event to sound category
  case "$EVENT" in
    SessionStart)      CATEGORY="greeting" ;;
    UserPromptSubmit)  CATEGORY="acknowledge" ;;
    Stop)              CATEGORY="complete" ;;
    Notification)      CATEGORY="alert" ;;
    *)                 exit 0 ;;
  esac

  # --- Cached config: parse once with jq, reuse as sourceable bash ---
  # Rebuild cache when config.json or manifest changes (mtime check)
  _rebuild_cache() {
    [[ -f "$CONFIG_FILE" ]] || return 1

    local enabled volume active_pack manifest
    read -r enabled volume active_pack <<< \
      "$(jq -r '[.enabled, (.volume // 0.5), (.active_pack // "new-who")] | @tsv' "$CONFIG_FILE")"

    manifest="${PLUGIN_ROOT}/packs/${active_pack}/manifest.json"
    [[ -f "$manifest" ]] || return 1

    [[ -d "$STATE_DIR" ]] || mkdir -p "$STATE_DIR"

    # Write sourceable cache file
    {
      echo "_ENABLED=${enabled}"
      echo "_VOLUME=${volume}"
      echo "_PACK=${active_pack}"
      echo "_MANIFEST=${manifest}"

      # Category toggles
      for cat in greeting acknowledge complete alert; do
        local val
        val=$(jq -r --arg c "$cat" '.categories[$c] // true' "$CONFIG_FILE")
        echo "_CAT_${cat}=${val}"
      done

      # Sound arrays per category
      jq -r '.sounds | to_entries[] | "_SOUNDS_\(.key)=(\(.value | map("\"" + . + "\"") | join(" ")))"' "$manifest"

      # Audio player detection
      local player=""
      if command -v afplay &>/dev/null; then
        player="afplay"
      elif command -v paplay &>/dev/null; then
        player="paplay"
      elif command -v mpv &>/dev/null; then
        player="mpv"
      elif command -v aplay &>/dev/null; then
        player="aplay"
      fi
      echo "_PLAYER=${player}"
    } > "$CACHE_FILE"
  }

  # Check if cache needs rebuilding
  CACHE_STALE=false
  if [[ ! -f "$CACHE_FILE" ]]; then
    CACHE_STALE=true
  elif [[ -f "$CONFIG_FILE" && "$CONFIG_FILE" -nt "$CACHE_FILE" ]]; then
    CACHE_STALE=true
  else
    # Quick check: read pack name from cache to find manifest path
    _cached_pack=$(grep -m1 '^_PACK=' "$CACHE_FILE" 2>/dev/null | cut -d= -f2-)
    _cached_manifest="${PLUGIN_ROOT}/packs/${_cached_pack}/manifest.json"
    if [[ -f "$_cached_manifest" && "$_cached_manifest" -nt "$CACHE_FILE" ]]; then
      CACHE_STALE=true
    fi
  fi

  if [[ "$CACHE_STALE" == "true" ]]; then
    _rebuild_cache || exit 0
  fi

  # Source the cache -- pure bash, zero jq
  source "$CACHE_FILE"

  # Check enabled + category
  if [[ "$_ENABLED" != "true" ]]; then
    exit 0
  fi
  _cat_var="_CAT_${CATEGORY}"
  if [[ "${!_cat_var}" != "true" ]]; then
    exit 0
  fi

  # Get sounds for this category from cached arrays
  _sounds_var="_SOUNDS_${CATEGORY}[@]"
  SOUNDS=("${!_sounds_var}")
  SOUND_COUNT=${#SOUNDS[@]}

  if [[ "$SOUND_COUNT" -eq 0 ]]; then
    exit 0
  fi

  # Pick a random sound, avoiding the last-played
  LAST_PLAYED_FILE="${STATE_DIR}/last_${CATEGORY}"
  LAST_PLAYED=""
  if [[ -f "$LAST_PLAYED_FILE" ]]; then
    LAST_PLAYED=$(<"$LAST_PLAYED_FILE")
  fi

  if [[ "$SOUND_COUNT" -eq 1 ]]; then
    SOUND_FILE="${SOUNDS[0]}"
  else
    for _ in 1 2 3; do
      SOUND_FILE="${SOUNDS[$((RANDOM % SOUND_COUNT))]}"
      [[ "$SOUND_FILE" != "$LAST_PLAYED" ]] && break
    done
  fi

  SOUND_PATH="${PLUGIN_ROOT}/sounds/${SOUND_FILE}"
  echo "$SOUND_FILE" > "$LAST_PLAYED_FILE"

  if [[ ! -f "$SOUND_PATH" ]]; then
    exit 0
  fi

  # Play sound
  case "$_PLAYER" in
    afplay) afplay -v "$_VOLUME" "$SOUND_PATH" ;;
    paplay) paplay --volume="$(echo "$_VOLUME * 65536" | bc | cut -d. -f1)" "$SOUND_PATH" ;;
    mpv)    mpv --no-terminal --volume="$(echo "$_VOLUME * 100" | bc | cut -d. -f1)" "$SOUND_PATH" ;;
    aplay)  aplay -q "$SOUND_PATH" ;;
  esac
) &>/dev/null &
disown 2>/dev/null
exit 0
